# frozen_string_literal: true

module WestanPoints
  class VipAccessService
    class << self
      def grant!(redemption:, reward:, now: Time.zone.now)
        raise Discourse::InvalidParameters.new(:reward_type) unless reward.vip_group_access?

        group = vip_group!
        user = redemption.user
        current_time = now.in_time_zone

        expire_due_for!(user_id: user.id, group_id: group.id, now: current_time)

        active_grants =
          VipGrant
            .active_at(current_time)
            .where(user_id: user.id, group_id: group.id)
            .lock
            .order(expires_at: :desc, id: :desc)
            .to_a
        membership_exists = GroupUser.exists?(group_id: group.id, user_id: user.id)
        remove_membership_on_expiry =
          if active_grants.any?
            active_grants.first.remove_membership_on_expiry
          else
            !membership_exists
          end
        current_expiration = active_grants.map(&:expires_at).max
        starts_from = [current_time, current_expiration].compact.max

        group.add(user) unless membership_exists

        grant = VipGrant.create!(
          user: user,
          group: group,
          redemption: redemption,
          starts_at: current_time,
          expires_at: starts_from + reward.duration_days.days,
          remove_membership_on_expiry: remove_membership_on_expiry
        )

        redemption.update!(
          status: "fulfilled",
          processed_at: current_time,
          staff_note: "Acesso VIP ativado automaticamente até #{grant.expires_at.iso8601}"
        )
        Jobs.enqueue_in(
          grant.expires_at - current_time,
          :westan_points_expire_vip_grant,
          user_id: user.id,
          group_id: group.id
        )
        user.groups.reset
        grant
      end

      def expire_for_user!(user:, now: Time.zone.now)
        pairs =
          VipGrant
            .due_at(now)
            .where(user_id: user.id)
            .distinct
            .pluck(:user_id, :group_id)

        pairs.sum do |user_id, group_id|
          expire_due_for!(user_id: user_id, group_id: group_id, now: now)
        end
      end

      def expire_all_due!(now: Time.zone.now)
        pairs = VipGrant.due_at(now).distinct.pluck(:user_id, :group_id)

        pairs.sum do |user_id, group_id|
          expire_due_for!(user_id: user_id, group_id: group_id, now: now)
        rescue StandardError => error
          Rails.logger.error(
            "[#{WestanPoints::PLUGIN_NAME}] Failed to expire VIP access for user #{user_id}: #{error.class}: #{error.message}"
          )
          0
        end
      end

      def expire_due_for!(user_id:, group_id:, now: Time.zone.now)
        expired_count = 0
        current_time = now.in_time_zone

        VipGrant.transaction do
          due_grants =
            VipGrant
              .due_at(current_time)
              .where(user_id: user_id, group_id: group_id)
              .lock
              .to_a
          next if due_grants.empty?

          due_grants.each { |grant| grant.update!(revoked_at: current_time) }
          expired_count = due_grants.length

          has_active_grant =
            VipGrant.active_at(current_time).exists?(user_id: user_id, group_id: group_id)
          final_grant = due_grants.max_by { |grant| [grant.expires_at, grant.id] }
          next if has_active_grant || !final_grant.remove_membership_on_expiry?

          group = Group.find_by(id: group_id)
          user = User.find_by(id: user_id)
          next unless group && user
          next if Ledger.multiplier_eligible?(user)

          group.remove(user) if GroupUser.exists?(group_id: group.id, user_id: user.id)
          user.groups.reset
        end

        expired_count
      end

      def vip_group!
        setting_value =
          SiteSetting.westan_points_vip_group.to_s.strip.delete_prefix("@")
        group = Group.find_by(id: setting_value.to_i) if setting_value.match?(/\A\d+\z/)
        if !group && setting_value.present?
          group = Group.where("LOWER(name) = ?", setting_value.downcase).first
        end

        unless group && !group.automatic?
          raise Discourse::InvalidAccess.new("O grupo VIP configurado não está disponível")
        end

        group
      end
    end
  end
end
