# frozen_string_literal: true

module Jobs
  class WestanPointsExpireVipGrants < ::Jobs::Scheduled
    every 15.minutes

    def execute(_args)
      return unless SiteSetting.westan_points_enabled

      ::WestanPoints::VipAccessService.expire_all_due!
    end
  end
end
