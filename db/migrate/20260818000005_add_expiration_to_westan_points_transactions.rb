# frozen_string_literal: true

class AddExpirationToWestanPointsTransactions < ActiveRecord::Migration[7.0]
  def change
    add_column :westan_points_transactions, :expires_at, :datetime
    add_index :westan_points_transactions, :expires_at

    reversible do |direction|
      direction.up do
        execute <<~SQL
          UPDATE westan_points_transactions
          SET expires_at = date_trunc('month', created_at) +
            ((4 - MOD(EXTRACT(MONTH FROM created_at)::integer - 3 + 12, 3)) * INTERVAL '1 month')
          WHERE kind IN ('post', 'topic') AND expires_at IS NULL
        SQL
      end
    end
  end
end
