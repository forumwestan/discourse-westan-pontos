# frozen_string_literal: true

module Jobs
  class WestanPointsExpirePoints < ::Jobs::Scheduled
    every 1.day

    def execute(_args)
      return unless SiteSetting.westan_points_enabled

      ::WestanPoints::Ledger.expire_all_due!
    end
  end
end
