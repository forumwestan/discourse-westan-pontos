# frozen_string_literal: true

module WestanPoints
  class Transaction < ActiveRecord::Base
    self.table_name = "westan_points_transactions"

    KINDS = %w[post topic redemption refund adjustment expiration transfer_in transfer_out].freeze

    belongs_to :wallet, class_name: "WestanPoints::Wallet", inverse_of: :transactions
    belongs_to :user

    validates :kind, inclusion: { in: KINDS }
    validates :amount, :balance_after, numericality: { only_integer: true }
    validates :event_key, uniqueness: true, allow_nil: true

    scope :active, -> { where(reversed_at: nil) }
    scope :recent_first, -> { order(created_at: :desc, id: :desc) }
  end
end
