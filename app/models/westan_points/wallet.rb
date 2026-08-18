# frozen_string_literal: true

module WestanPoints
  class Wallet < ActiveRecord::Base
    self.table_name = "westan_points_wallets"

    belongs_to :user
    has_many :transactions,
             class_name: "WestanPoints::Transaction",
             dependent: :destroy,
             inverse_of: :wallet

    validates :user_id, uniqueness: true
    validates :balance, :lifetime_earned, :lifetime_spent, numericality: { only_integer: true }

    def self.for_user!(user)
      find_or_create_by!(user_id: user.id)
    rescue ActiveRecord::RecordNotUnique
      find_by!(user_id: user.id)
    end
  end
end
