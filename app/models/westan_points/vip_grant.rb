# frozen_string_literal: true

module WestanPoints
  class VipGrant < ActiveRecord::Base
    self.table_name = "westan_points_vip_grants"

    belongs_to :user
    belongs_to :group
    belongs_to :redemption,
               class_name: "WestanPoints::Redemption",
               inverse_of: :vip_grant

    validates :redemption_id, uniqueness: true
    validates :starts_at, :expires_at, presence: true
    validate :expiration_after_start

    scope :not_revoked, -> { where(revoked_at: nil) }
    scope :active_at, ->(time) { not_revoked.where("starts_at <= ? AND expires_at > ?", time, time) }
    scope :due_at, ->(time) { not_revoked.where("expires_at <= ?", time) }

    def active?(time = Time.zone.now)
      revoked_at.nil? && starts_at <= time && expires_at > time
    end

    private

    def expiration_after_start
      return if starts_at.blank? || expires_at.blank? || expires_at > starts_at

      errors.add(:expires_at, "must be after starts_at")
    end
  end
end
