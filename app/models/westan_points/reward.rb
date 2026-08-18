# frozen_string_literal: true

module WestanPoints
  class Reward < ActiveRecord::Base
    self.table_name = "westan_points_rewards"

    REWARD_TYPES = %w[manual vip_group_access].freeze

    has_many :redemptions,
             class_name: "WestanPoints::Redemption",
             dependent: :restrict_with_error,
             inverse_of: :reward

    validates :title, presence: true, length: { maximum: 120 }
    validates :cost, numericality: { only_integer: true, greater_than: 0 }
    validates :stock,
              numericality: { only_integer: true, greater_than_or_equal_to: 0 },
              allow_nil: true
    validates :sort_order, numericality: { only_integer: true }
    validates :reward_type, inclusion: { in: REWARD_TYPES }
    validates :duration_days,
              numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 3_650 },
              presence: true,
              if: :vip_group_access?

    scope :available_catalog, -> { where(enabled: true).where("stock IS NULL OR stock > 0") }
    scope :ordered, -> { order(:sort_order, :cost, :id) }

    def in_stock?
      stock.nil? || stock.positive?
    end

    def vip_group_access?
      reward_type == "vip_group_access"
    end
  end
end
