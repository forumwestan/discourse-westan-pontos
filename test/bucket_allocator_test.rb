# frozen_string_literal: true

require "minitest/autorun"
require_relative "../app/services/westan_points/bucket_allocator"

class BucketAllocatorTest < Minitest::Test
  Entry = Struct.new(:id, :amount, :expires_at, :metadata)
  OCTOBER = Time.utc(2026, 10, 1)
  JANUARY = Time.utc(2027, 1, 1)

  def entry(id, amount, expiry = nil, metadata = {})
    Entry.new(id, amount, expiry, metadata)
  end

  def remaining(*entries)
    WestanPoints::BucketAllocator.remaining(entries)
  end

  def test_debits_consume_soonest_expiring_points
    result = remaining(entry(1, 100, JANUARY), entry(2, 50, OCTOBER), entry(3, -70))
    assert_equal [80], result.map { |b| b[:amount] }
    assert_equal JANUARY, result.first[:expires_at]
  end

  def test_old_spending_does_not_consume_later_incoming_transfer
    result = remaining(entry(1, 100, JANUARY), entry(2, -100), entry(3, 50, OCTOBER))
    assert_equal 50, result.sum { |b| b[:amount] }
    assert_equal OCTOBER, result.first[:expires_at]
  end

  def test_transfer_preserves_multiple_expiration_dates
    parts = [{ "amount" => 30, "expires_at" => OCTOBER.iso8601 },
             { "amount" => 70, "expires_at" => JANUARY.iso8601 }]
    result = remaining(entry(1, 100, OCTOBER, "expiration_buckets" => parts), entry(2, -40))
    assert_equal [60], result.map { |b| b[:amount] }
    assert_equal JANUARY, result.first[:expires_at]
  end

  def test_expiration_and_later_receipt_do_not_expire_points_twice
    result = remaining(entry(1, 30, OCTOBER), entry(2, -30), entry(3, 50, JANUARY))
    assert_equal 50, result.sum { |b| b[:amount] }
    assert_equal JANUARY, result.first[:expires_at]
  end

  def test_negative_balance_after_source_reversal_consumes_future_credit
    result = remaining(entry(2, -30), entry(3, 50, JANUARY))
    assert_equal 20, result.sum { |b| b[:amount] }
  end

  def test_undated_adjustments_are_used_last
    result = remaining(entry(1, 100), entry(2, 50, OCTOBER), entry(3, -60))
    assert_equal [90], result.map { |b| b[:amount] }
    assert_nil result.first[:expires_at]
  end
end
