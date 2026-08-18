# frozen_string_literal: true

class CreateWestanPointsRedemptions < ActiveRecord::Migration[7.0]
  def change
    create_table :westan_points_redemptions do |t|
      t.bigint :user_id, null: false
      t.bigint :reward_id, null: false
      t.integer :cost, null: false
      t.string :status, null: false, default: "pending"
      t.text :user_note, null: false, default: ""
      t.text :staff_note, null: false, default: ""
      t.bigint :processed_by_id
      t.datetime :processed_at
      t.timestamps
    end

    add_index :westan_points_redemptions, :user_id
    add_index :westan_points_redemptions, :reward_id
    add_index :westan_points_redemptions, %i[status created_at]
  end
end
