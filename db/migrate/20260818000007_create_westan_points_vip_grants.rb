# frozen_string_literal: true

class CreateWestanPointsVipGrants < ActiveRecord::Migration[7.0]
  def change
    create_table :westan_points_vip_grants do |t|
      t.bigint :user_id, null: false
      t.bigint :group_id, null: false
      t.bigint :redemption_id, null: false
      t.datetime :starts_at, null: false
      t.datetime :expires_at, null: false
      t.boolean :remove_membership_on_expiry, null: false, default: true
      t.datetime :revoked_at
      t.timestamps
    end

    add_index :westan_points_vip_grants, :redemption_id, unique: true
    add_index :westan_points_vip_grants, %i[user_id group_id]
    add_index :westan_points_vip_grants, %i[revoked_at expires_at]
  end
end
