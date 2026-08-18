# frozen_string_literal: true

module WestanPoints
  class RedemptionService
    class << self
      def redeem!(user:, reward:, user_note: "")
        Ledger.expire_due_points!(user: user)

        Redemption.transaction do
          locked_reward = Reward.lock.find(reward.id)
          raise Discourse::InvalidAccess.new("Benefício indisponível") unless locked_reward.enabled?
          raise Discourse::InvalidAccess.new("Benefício sem estoque") unless locked_reward.in_stock?

          wallet = Wallet.for_user!(user)
          wallet = Wallet.lock.find(wallet.id)
          redemption = Redemption.create!(
            user: user,
            reward: locked_reward,
            cost: locked_reward.cost,
            status: "pending",
            user_note: user_note.to_s.strip.first(500)
          )

          Ledger.debit_locked!(
            wallet: wallet,
            amount: locked_reward.cost,
            event_key: "redemption:#{redemption.id}",
            description: "Troca: #{locked_reward.title}",
            metadata: { redemption_id: redemption.id, reward_id: locked_reward.id }
          )

          locked_reward.update!(stock: locked_reward.stock - 1) unless locked_reward.stock.nil?
          if locked_reward.vip_group_access?
            VipAccessService.grant!(redemption: redemption, reward: locked_reward)
          end
          redemption
        end
      end

      def update_status!(redemption:, status:, staff:, staff_note: "")
        target_status = status.to_s
        raise Discourse::InvalidParameters.new(:status) unless Redemption::STATUSES.include?(target_status)

        Redemption.transaction do
          locked_redemption = Redemption.lock.find(redemption.id)
          previous_status = locked_redemption.status
          validate_transition!(previous_status, target_status)

          if target_status == "rejected" && previous_status != "rejected"
            refund!(locked_redemption, staff)
          end

          locked_redemption.update!(
            status: target_status,
            staff_note: staff_note.to_s.strip.first(1_000),
            processed_by: staff,
            processed_at: Time.zone.now
          )
          locked_redemption
        end
      end

      private

      def validate_transition!(from, to)
        return if from == to

        allowed = {
          "pending" => %w[approved rejected],
          "approved" => %w[fulfilled rejected],
          "fulfilled" => [],
          "rejected" => []
        }
        return if allowed.fetch(from, []).include?(to)

        raise Discourse::InvalidAccess.new("Transição de status inválida")
      end

      def refund!(redemption, staff)
        wallet = Wallet.lock.find_by!(user_id: redemption.user_id)
        Ledger.refund_locked!(
          wallet: wallet,
          amount: redemption.cost,
          event_key: "redemption-refund:#{redemption.id}",
          description: "Estorno: #{redemption.reward.title}",
          metadata: {
            redemption_id: redemption.id,
            reward_id: redemption.reward_id,
            actor_id: staff.id
          }
        )

        reward = Reward.lock.find(redemption.reward_id)
        reward.update!(stock: reward.stock + 1) unless reward.stock.nil?
      end
    end
  end
end
