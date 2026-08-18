# frozen_string_literal: true

class CreateWestanPointsTransactions < ActiveRecord::Migration[7.0]
  def change
    create_table :westan_points_transactions do |t|
      t.bigint :wallet_id, null: false
      t.bigint :user_id, null: false
      t.integer :amount, null: false
      t.integer :balance_after, null: false
      t.string :kind, null: false
      t.string :event_key
      t.string :source_type
      t.bigint :source_id
      t.string :description, null: false, default: ""
      t.jsonb :metadata, null: false, default: {}
      t.datetime :reversed_at
      t.timestamps
    end

    add_index :westan_points_transactions, :wallet_id
    add_index :westan_points_transactions, :user_id
    add_index :westan_points_transactions, :event_key, unique: true
    add_index :westan_points_transactions, %i[source_type source_id]
    add_index :westan_points_transactions, %i[user_id created_at]
  end
end
