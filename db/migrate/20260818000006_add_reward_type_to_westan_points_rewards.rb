# frozen_string_literal: true

class AddRewardTypeToWestanPointsRewards < ActiveRecord::Migration[7.0]
  def change
    add_column :westan_points_rewards, :reward_type, :string, null: false, default: "manual"
    add_column :westan_points_rewards, :duration_days, :integer
    add_index :westan_points_rewards, :reward_type
  end
end
