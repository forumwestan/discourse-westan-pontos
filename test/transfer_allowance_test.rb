# Standalone checks of monthly accounting; Rails database coverage is in spec/services.
require "minitest/autorun"
require "date"
require_relative "../app/services/westan_points/transfer_service"

class AllowanceTime < DateTime
  def in_time_zone; self; end
  def beginning_of_month; self.class.civil(year, month, 1, 0, 0, 0, offset); end
  def advance(months:); self >> months; end
end

module WestanPoints
  module Ledger
    def self.multiplier_eligible?(user); user.premium; end
  end
  class Transaction
    class << self; attr_accessor :rows; end
    def self.where(filters)
      Scope.new(rows.select { |row| filters.all? { |key, value| value.is_a?(Range) ? value.cover?(row[key]) : row[key] == value } })
    end
    class Scope
      def initialize(rows); @rows = rows; end
      def where(condition)
        raise "Unexpected query" unless condition == "amount < 0"
        self.class.new(@rows.select { |row| row[:amount] < 0 })
      end
      def sum(key); @rows.sum { |row| row[key] }; end
    end
  end
end

class TransferAllowanceTest < Minitest::Test
  User = Struct.new(:id, :premium)
  def setup
    @user = User.new(1, false)
    @now = AllowanceTime.parse("2026-09-19T12:00:00-03:00")
    WestanPoints::Transaction.rows = []
  end
  def entry(amount, at: @now, kind: "transfer_out", user_id: 1)
    WestanPoints::Transaction.rows << { amount: amount, created_at: at, kind: kind, user_id: user_id }
  end
  def allowance(now = @now)
    WestanPoints::TransferService.monthly_allowance(user: @user, now: now)
  end
  def test_accumulation_and_current_membership
    entry(-120); entry(-80)
    assert_equal [200, 200, 0], allowance.values_at(:limit, :sent, :remaining)
    @user.premium = true
    assert_equal [400, 200, 200], allowance.values_at(:limit, :sent, :remaining)
    entry(-200)
    @user.premium = false
    assert_equal 0, allowance[:remaining]
  end
  def test_other_movements_do_not_consume_or_replenish_allowance
    entry(-25)
    entry(150, kind: "transfer_in"); entry(-50, kind: "redemption")
    entry(200, kind: "adjustment"); entry(-100, user_id: 2)
    assert_equal 25, allowance[:sent]
    assert_equal 175, allowance[:remaining]
  end
  def test_exclusive_month_boundaries_including_year_change
    entry(-80, at: AllowanceTime.parse("2026-08-31T23:59:59-03:00"))
    entry(-50, at: AllowanceTime.parse("2026-09-01T00:00:00-03:00"))
    entry(-20, at: AllowanceTime.parse("2026-10-01T00:00:00-03:00"))
    assert_equal 50, allowance[:sent]
    assert_equal AllowanceTime.parse("2026-10-01T00:00:00-03:00"), allowance[:resets_at]
    assert_equal 20, allowance(allowance[:resets_at])[:sent]
    december = AllowanceTime.parse("2026-12-31T23:59:59-03:00")
    assert_equal AllowanceTime.parse("2027-01-01T00:00:00-03:00"), allowance(december)[:resets_at]
  end
end
