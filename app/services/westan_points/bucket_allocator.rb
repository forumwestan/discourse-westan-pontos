# frozen_string_literal: true

require "time"

module WestanPoints
  # Replay in insertion order: a past debit must not consume a later incoming
  # transfer just because that transfer has an earlier expiration date.
  class BucketAllocator
    def self.remaining(transactions)
      buckets = []
      debt = 0
      transactions.each do |transaction|
        if transaction.amount.positive?
          parts = transaction.metadata["expiration_buckets"]
          parts = [{ "amount" => transaction.amount, "expires_at" => transaction.expires_at }] unless parts
          parts.each do |part|
            amount = part.fetch("amount").to_i
            used = [amount, debt].min
            debt -= used
            expiry = part["expires_at"]
            expiry = Time.iso8601(expiry) if expiry.is_a?(String)
            buckets << { transaction_id: transaction.id, amount: amount - used, expires_at: expiry }
          end
        else
          consumed = -transaction.amount
          buckets.sort_by! { |b| [b[:expires_at] ? 0 : 1, b[:expires_at]&.to_i || 0, b[:transaction_id]] }
          buckets.each do |bucket|
            used = [bucket[:amount], consumed].min
            bucket[:amount] -= used
            consumed -= used
            break if consumed.zero?
          end
          debt += consumed
        end
      end
      buckets.select { |b| b[:amount].positive? }.sort_by do |b|
        [b[:expires_at] ? 0 : 1, b[:expires_at]&.to_i || 0, b[:transaction_id]]
      end
    end
  end
end
