# frozen_string_literal: true

namespace :westan_points do
  desc "Import eligible posts into Westan Points for a date range"
  task backfill: :environment do
    start_at = Time.zone.parse(ENV.fetch("START_AT", "2026-08-01 00:00:00"))
    end_at =
      ENV["END_AT"].present? ? Time.zone.parse(ENV["END_AT"]) : Time.zone.now

    abort "Invalid START_AT" unless start_at
    abort "Invalid END_AT" unless end_at
    abort "Westan Points is disabled" unless SiteSetting.westan_points_enabled

    puts "Importing eligible posts from #{start_at.iso8601} through #{end_at.iso8601}..."

    result =
      WestanPoints::Ledger.backfill_posts!(start_at: start_at, end_at: end_at) do |stats|
        puts "Processed #{stats[:processed]}/#{stats[:candidates]} posts..."
      end

    puts "Import complete."
    puts "Candidates: #{result[:candidates]}"
    puts "Awarded posts: #{result[:awarded]}"
    puts "Points awarded: #{result[:points_awarded]}"
    puts "Skipped: #{result[:skipped]}"
    puts "Failed: #{result[:failed]}"
  end
end
