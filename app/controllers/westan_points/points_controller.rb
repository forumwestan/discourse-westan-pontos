# frozen_string_literal: true

require "uri"

module WestanPoints
  class PointsController < ::ApplicationController
    requires_plugin WestanPoints::PLUGIN_NAME

    before_action :ensure_logged_in
    before_action :ensure_staff, only: %i[
      create_reward
      update_reward
      update_redemption
      adjust_balance
    ]

    def index
      VipAccessService.expire_for_user!(user: current_user)
      Ledger.expire_due_points!(user: current_user)
      wallet = Wallet.for_user!(current_user)
      rewards = Reward.available_catalog.ordered.to_a

      render json: {
        wallet: wallet_payload(wallet),
        is_vip: Ledger.vip_member?(current_user),
        rules: rules_payload,
        rewards: rewards.map { |reward| reward_payload(reward, wallet) },
        transactions: wallet.transactions.recent_first.limit(30).map { |item| transaction_payload(item) },
        redemptions: Redemption.where(user_id: current_user.id).includes(:reward, :vip_grant).recent_first.limit(30).map { |item| redemption_payload(item) },
        admin: staff_payload
      }
    end

    def redeem
      reward = Reward.find(params.require(:reward_id))
      redemption = RedemptionService.redeem!(
        user: current_user,
        reward: reward,
        user_note: params[:user_note]
      )

      render json: {
        success: true,
        redemption: redemption_payload(redemption),
        wallet: wallet_payload(Wallet.find_by!(user_id: current_user.id))
      }
    end

    def create_reward
      reward = Reward.create!(reward_attributes)
      render json: { success: true, reward: reward_payload(reward) }
    end

    def update_reward
      reward = Reward.find(params[:id])
      reward.update!(reward_attributes)
      render json: { success: true, reward: reward_payload(reward) }
    end

    def update_redemption
      redemption = Redemption.find(params[:id])
      updated = RedemptionService.update_status!(
        redemption: redemption,
        status: params.require(:status),
        staff: current_user,
        staff_note: params[:staff_note]
      )
      render json: { success: true, redemption: redemption_payload(updated) }
    end

    def adjust_balance
      user = User.find_by(id: params[:user_id]) || User.find_by(username_lower: params[:username].to_s.downcase)
      raise Discourse::NotFound unless user

      wallet = Ledger.adjust!(
        user: user,
        amount: params.require(:amount),
        description: params[:description],
        actor: current_user
      )
      render json: { success: true, wallet: wallet_payload(wallet), user: user_payload(user) }
    end

    private

    def ensure_staff
      raise Discourse::InvalidAccess unless current_user&.staff?
    end

    def reward_attributes
      stock_value = params[:stock].presence
      reward_type = params[:reward_type].presence || "manual"
      {
        title: params.require(:title).to_s.strip.first(120),
        description: params[:description].to_s.strip.first(2_000),
        cost: params.require(:cost).to_i,
        stock: stock_value.nil? ? nil : stock_value.to_i,
        enabled: ActiveModel::Type::Boolean.new.cast(params.fetch(:enabled, true)),
        image_url: normalized_image_url,
        fulfillment_instructions: params[:fulfillment_instructions].to_s.strip.first(2_000),
        sort_order: params[:sort_order].to_i,
        reward_type: reward_type,
        duration_days: reward_type == "vip_group_access" ? params[:duration_days].to_i : nil
      }
    end

    def rules_payload
      {
        points_per_post: SiteSetting.westan_points_per_post.to_i,
        points_per_topic: SiteSetting.westan_points_per_topic.to_i,
        vip_multiplier: SiteSetting.westan_points_vip_multiplier.to_i,
        vip_group: SiteSetting.westan_points_vip_group.to_s,
        expiration_cycle_months: Ledger::EXPIRATION_CYCLE_MONTHS,
        expiration_grace_months: Ledger::EXPIRATION_GRACE_MONTHS
      }
    end

    def wallet_payload(wallet)
      {
        balance: wallet.balance,
        lifetime_earned: wallet.lifetime_earned,
        lifetime_spent: wallet.lifetime_spent,
        next_expiration: Ledger.expiration_summary(user: wallet.user)
      }
    end

    def reward_payload(reward, wallet = nil, include_internal: false)
      payload = {
        id: reward.id,
        title: reward.title,
        description: reward.description,
        cost: reward.cost,
        stock: reward.stock,
        enabled: reward.enabled,
        image_url: reward.image_url,
        sort_order: reward.sort_order,
        reward_type: reward.reward_type,
        duration_days: reward.duration_days,
        automatic_fulfillment: reward.vip_group_access?,
        in_stock: reward.in_stock?,
        can_redeem: wallet ? reward.enabled? && reward.in_stock? && wallet.balance >= reward.cost : nil
      }
      payload[:fulfillment_instructions] = reward.fulfillment_instructions if include_internal
      payload
    end

    def transaction_payload(transaction)
      {
        id: transaction.id,
        amount: transaction.amount,
        balance_after: transaction.balance_after,
        kind: transaction.kind,
        description: transaction.description,
        reversed: transaction.reversed_at.present?,
        expires_at: transaction.expires_at,
        created_at: transaction.created_at
      }
    end

    def redemption_payload(redemption)
      {
        id: redemption.id,
        user: user_payload(redemption.user),
        reward: {
          id: redemption.reward.id,
          title: redemption.reward.title,
          image_url: redemption.reward.image_url
        },
        cost: redemption.cost,
        status: redemption.status,
        user_note: redemption.user_note,
        staff_note: redemption.staff_note,
        vip_grant: vip_grant_payload(redemption.vip_grant),
        created_at: redemption.created_at,
        processed_at: redemption.processed_at
      }
    end

    def user_payload(user)
      {
        id: user.id,
        username: user.username,
        display_name: user.name.presence || user.username,
        avatar_url: user.avatar_template&.gsub("{size}", "64")
      }
    end

    def vip_grant_payload(grant)
      return nil unless grant

      {
        starts_at: grant.starts_at,
        expires_at: grant.expires_at,
        active: grant.active?
      }
    end

    def staff_payload
      return nil unless current_user&.staff?

      {
        rewards: Reward.ordered.map { |reward| reward_payload(reward, nil, include_internal: true) },
        redemptions: Redemption.includes(:user, :reward, :vip_grant).recent_first.limit(100).map { |item| redemption_payload(item) }
      }
    end

    def normalized_image_url
      value = params[:image_url].to_s.strip.first(1_000)
      return "" if value.blank?

      uri = URI.parse(value)
      return value if uri.is_a?(URI::HTTP) && uri.host.present?

      raise Discourse::InvalidParameters.new(:image_url)
    rescue URI::InvalidURIError
      raise Discourse::InvalidParameters.new(:image_url)
    end
  end
end
