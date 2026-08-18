# frozen_string_literal: true

class CreateWestanPointsWallets < ActiveRecord::Migration[7.0]
  def change
    create_table :westan_points_wallets do |t|
      t.bigint :user_id, null: false
      t.integer :balance, null: false, default: 0
      t.integer :lifetime_earned, null: false, default: 0
      t.integer :lifetime_spent, null: false, default: 0
      t.timestamps
    end

    add_index :westan_points_wallets, :user_id, unique: true
  end
end
