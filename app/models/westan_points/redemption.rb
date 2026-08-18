# frozen_string_literal: true

module WestanPoints
  class Redemption < ActiveRecord::Base
    self.table_name = "westan_points_redemptions"

    STATUSES = %w[pending approved fulfilled rejected].freeze

    belongs_to :user
    belongs_to :reward, class_name: "WestanPoints::Reward", inverse_of: :redemptions
    belongs_to :processed_by, class_name: "User", optional: true
    has_one :vip_grant,
            class_name: "WestanPoints::VipGrant",
            dependent: :restrict_with_error,
            inverse_of: :redemption

    validates :status, inclusion: { in: STATUSES }
    validates :cost, numericality: { only_integer: true, greater_than: 0 }

    scope :recent_first, -> { order(created_at: :desc, id: :desc) }
  end
end
