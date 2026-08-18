# frozen_string_literal: true

class CreateWestanPointsRewards < ActiveRecord::Migration[7.0]
  def change
    create_table :westan_points_rewards do |t|
      t.string :title, null: false
      t.text :description, null: false, default: ""
      t.integer :cost, null: false
      t.integer :stock
      t.boolean :enabled, null: false, default: true
      t.string :image_url, null: false, default: ""
      t.text :fulfillment_instructions, null: false, default: ""
      t.integer :sort_order, null: false, default: 0
      t.timestamps
    end

    add_index :westan_points_rewards, %i[enabled sort_order]
  end
end
