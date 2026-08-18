# frozen_string_literal: true

require "set"

module WestanPoints
  class Ledger
    EXPIRATION_CYCLE_MONTHS = 3
    EXPIRATION_GRACE_MONTHS = 1
    EXPIRATION_ANCHOR_MONTH = 3

    class << self
      def process_post(post, action)
        return unless SiteSetting.westan_points_enabled

        case action.to_sym
        when :created
          award_post(post)
        when :destroyed
          reverse_post(post)
        when :recovered
          restore_post(post)
        end
      rescue StandardError => error
        Rails.logger.error(
          "[#{WestanPoints::PLUGIN_NAME}] Failed to process post #{post&.id}: #{error.class}: #{error.message}"
        )
      end

      def award_post(post)
        return unless eligible_post?(post)

        details = award_details(post)
        record_award!(post.user, details)
      end

      def reverse_post(post)
        details = award_details(post)
        reverse_award!(details[:event_key])
      end

      def restore_post(post)
        return unless eligible_post?(post)

        details = award_details(post)
        transaction = Transaction.find_by(event_key: details[:event_key])

        if transaction
          restore_award!(transaction)
        else
          record_award!(post.user, details)
        end
      end

      def adjust!(user:, amount:, description:, actor:)
        raise Discourse::InvalidParameters.new(:amount) if amount.to_i.zero?

        Wallet.transaction do
          wallet = locked_wallet(user)
          value = amount.to_i
          wallet.update!(
            balance: wallet.balance + value,
            lifetime_earned: wallet.lifetime_earned + [value, 0].max,
            lifetime_spent: wallet.lifetime_spent + [-value, 0].max
          )
          Transaction.create!(
            wallet: wallet,
            user: user,
            amount: value,
            balance_after: wallet.balance,
            kind: "adjustment",
            description: description.to_s.presence || "Ajuste manual",
            metadata: { actor_id: actor.id }
          )
          wallet
        end
      end

      def debit_locked!(wallet:, amount:, event_key:, description:, metadata: {})
        value = amount.to_i
        raise Discourse::InvalidParameters.new(:amount) unless value.positive?
        raise Discourse::InvalidAccess.new("Saldo insuficiente") if wallet.balance < value

        wallet.update!(
          balance: wallet.balance - value,
          lifetime_spent: wallet.lifetime_spent + value
        )
        Transaction.create!(
          wallet: wallet,
          user_id: wallet.user_id,
          amount: -value,
          balance_after: wallet.balance,
          kind: "redemption",
          event_key: event_key,
          description: description,
          metadata: metadata
        )
      end

      def refund_locked!(wallet:, amount:, event_key:, description:, metadata: {})
        value = amount.to_i
        raise Discourse::InvalidParameters.new(:amount) unless value.positive?

        wallet.update!(
          balance: wallet.balance + value,
          lifetime_spent: [wallet.lifetime_spent - value, 0].max
        )
        Transaction.create!(
          wallet: wallet,
          user_id: wallet.user_id,
          amount: value,
          balance_after: wallet.balance,
          kind: "refund",
          event_key: event_key,
          description: description,
          metadata: metadata,
          expires_at: expiration_date_for(Time.zone.now)
        )
      end

      def multiplier_eligible?(user)
        setting_value =
          SiteSetting.westan_points_eligible_vip_group.to_s.strip.delete_prefix("@")
        return false if setting_value.blank? || user.nil?

        group = Group.find_by(id: setting_value.to_i) if setting_value.match?(/\A\d+\z/)
        group ||= Group.where("LOWER(name) = ?", setting_value.downcase).first
        return false unless group

        user.groups.any? { |user_group| user_group.id == group.id }
      end

      def expiration_date_for(earned_at)
        earned_month = earned_at.in_time_zone.beginning_of_month
        position_in_cycle = (earned_month.month - EXPIRATION_ANCHOR_MONTH) % EXPIRATION_CYCLE_MONTHS
        months_until_expiration =
          EXPIRATION_CYCLE_MONTHS - position_in_cycle + EXPIRATION_GRACE_MONTHS

        earned_month.advance(months: months_until_expiration)
      end

      def expiration_summary(user:, now: Time.zone.now)
        current_time = now.in_time_zone
        future_buckets = remaining_buckets(user_id: user.id).select do |bucket|
          bucket[:expires_at].present? && bucket[:expires_at] > current_time
        end
        return nil if future_buckets.empty?

        next_expiration = future_buckets.map { |bucket| bucket[:expires_at] }.min
        amount = future_buckets.sum do |bucket|
          bucket[:expires_at].to_i == next_expiration.to_i ? bucket[:amount] : 0
        end

        { amount: amount, expires_at: next_expiration }
      end

      def expire_due_points!(user:, now: Time.zone.now)
        expired_amount = 0
        current_time = now.in_time_zone

        Wallet.transaction do
          wallet = locked_wallet(user)
          due_amount = remaining_buckets(user_id: user.id).sum do |bucket|
            bucket[:expires_at].present? && bucket[:expires_at] <= current_time ? bucket[:amount] : 0
          end
          expired_amount = [[due_amount, wallet.balance].min, 0].max
          next unless expired_amount.positive?

          wallet.update!(balance: wallet.balance - expired_amount)
          Transaction.create!(
            wallet: wallet,
            user: user,
            amount: -expired_amount,
            balance_after: wallet.balance,
            kind: "expiration",
            description: "Pontos expirados",
            metadata: {
              expired_at: current_time.iso8601,
              expiration_cycle_months: EXPIRATION_CYCLE_MONTHS,
              expiration_grace_months: EXPIRATION_GRACE_MONTHS
            }
          )
        end

        expired_amount
      end

      def expire_all_due!(now: Time.zone.now)
        user_ids =
          Transaction
            .active
            .where("amount > 0")
            .where.not(expires_at: nil)
            .where("expires_at <= ?", now)
            .distinct
            .pluck(:user_id)

        user_ids.sum do |user_id|
          user = User.find_by(id: user_id)
          next 0 unless user

          expire_due_points!(user: user, now: now)
        rescue StandardError => error
          Rails.logger.error(
            "[#{WestanPoints::PLUGIN_NAME}] Failed to expire points for user #{user_id}: #{error.class}: #{error.message}"
          )
          0
        end
      end

      def backfill_posts!(start_at:, end_at: Time.zone.now)
        start_time = start_at.in_time_zone
        end_time = end_at.in_time_zone
        raise ArgumentError, "start_at must be before end_at" unless start_time < end_time

        stats = {
          candidates: 0,
          processed: 0,
          awarded: 0,
          skipped: 0,
          failed: 0,
          points_awarded: 0
        }
        posts =
          Post
            .includes(:topic, user: :groups)
            .where(created_at: start_time..end_time)

        stats[:candidates] = posts.count
        posts.find_each(batch_size: 500) do |post|
          stats[:processed] += 1
          event_key =
            post.post_number.to_i == 1 ? "topic:#{post.topic_id}" : "post:#{post.id}"
          already_awarded = Transaction.active.exists?(event_key: event_key)

          begin
            award_post(post)
            transaction = Transaction.active.find_by(event_key: event_key)

            if !already_awarded && transaction
              stats[:awarded] += 1
              stats[:points_awarded] += transaction.amount
            else
              stats[:skipped] += 1
            end
          rescue StandardError => error
            stats[:failed] += 1
            Rails.logger.error(
              "[#{WestanPoints::PLUGIN_NAME}] Failed to backfill post #{post.id}: " \
                "#{error.class}: #{error.message}"
            )
          end

          yield(stats.dup) if block_given? && (stats[:processed] % 500).zero?
        end

        stats
      end

      private

      def remaining_buckets(user_id:)
        positives =
          Transaction
            .active
            .where(user_id: user_id)
            .where("amount > 0")
            .to_a
            .sort_by do |transaction|
              [
                transaction.expires_at.present? ? 0 : 1,
                transaction.expires_at&.to_i || 0,
                transaction.created_at.to_i,
                transaction.id
              ]
            end
        consumed = -Transaction.active.where(user_id: user_id).where("amount < 0").sum(:amount)

        positives.filter_map do |transaction|
          used = [consumed, transaction.amount].min
          consumed -= used
          remaining = transaction.amount - used
          next unless remaining.positive?

          {
            transaction_id: transaction.id,
            amount: remaining,
            expires_at: transaction.expires_at
          }
        end
      end

      def eligible_post?(post)
        return false unless post&.user && post.topic
        return false if post.deleted_at.present?
        return false unless post.post_type == Post.types[:regular]
        return false unless post.topic.archetype == Archetype.default
        return false if post.user.staged?
        return false if post.user_id == Discourse.system_user.id
        return false if excluded_category_ids.include?(post.topic.category_id.to_i)

        true
      end

      def excluded_category_ids
        SiteSetting.westan_points_excluded_categories.to_s.split("|").map(&:to_i).to_set
      end

      def award_details(post)
        is_topic = post.post_number.to_i == 1
        earned_at = (post.created_at || Time.zone.now).in_time_zone
        base_points =
          is_topic ? SiteSetting.westan_points_per_topic.to_i : SiteSetting.westan_points_per_post.to_i
        multiplier = multiplier_eligible?(post.user) ? SiteSetting.westan_points_vip_multiplier.to_i : 1
        amount = base_points * [multiplier, 1].max

        {
          event_key: is_topic ? "topic:#{post.topic_id}" : "post:#{post.id}",
          kind: is_topic ? "topic" : "post",
          source_type: is_topic ? "Topic" : "Post",
          source_id: is_topic ? post.topic_id : post.id,
          amount: amount,
          earned_at: earned_at,
          expires_at: expiration_date_for(earned_at),
          description: is_topic ? "Tópico criado" : "Post publicado",
          metadata: {
            base_points: base_points,
            multiplier: multiplier,
            topic_id: post.topic_id,
            post_id: post.id,
            earned_at: earned_at.iso8601,
            expires_at: expiration_date_for(earned_at).iso8601
          }
        }
      end

      def record_award!(user, details)
        return if details[:amount].zero?

        Wallet.transaction do
          existing = Transaction.lock.find_by(event_key: details[:event_key])
          return restore_award!(existing) if existing&.reversed_at
          return existing if existing

          wallet = locked_wallet(user)
          wallet.update!(
            balance: wallet.balance + details[:amount],
            lifetime_earned: wallet.lifetime_earned + details[:amount]
          )
          Transaction.create!(
            wallet: wallet,
            user: user,
            amount: details[:amount],
            balance_after: wallet.balance,
            kind: details[:kind],
            event_key: details[:event_key],
            source_type: details[:source_type],
            source_id: details[:source_id],
            description: details[:description],
            metadata: details[:metadata],
            expires_at: details[:expires_at],
            created_at: details[:earned_at],
            updated_at: details[:earned_at]
          )
        end
      rescue ActiveRecord::RecordNotUnique
        Transaction.find_by(event_key: details[:event_key])
      end

      def reverse_award!(event_key)
        Wallet.transaction do
          transaction = Transaction.lock.find_by(event_key: event_key)
          return unless transaction && transaction.reversed_at.nil?

          wallet = Wallet.lock.find(transaction.wallet_id)
          wallet.update!(
            balance: wallet.balance - transaction.amount,
            lifetime_earned: [wallet.lifetime_earned - transaction.amount, 0].max
          )
          transaction.update!(reversed_at: Time.zone.now, balance_after: wallet.balance)
        end
      end

      def restore_award!(transaction)
        Wallet.transaction do
          locked_transaction = Transaction.lock.find(transaction.id)
          return locked_transaction unless locked_transaction.reversed_at

          wallet = Wallet.lock.find(locked_transaction.wallet_id)
          wallet.update!(
            balance: wallet.balance + locked_transaction.amount,
            lifetime_earned: wallet.lifetime_earned + locked_transaction.amount
          )
          locked_transaction.update!(reversed_at: nil, balance_after: wallet.balance)
          locked_transaction
        end
      end

      def locked_wallet(user)
        Wallet.for_user!(user)
        Wallet.lock.find_by!(user_id: user.id)
      end
    end
  end
end
