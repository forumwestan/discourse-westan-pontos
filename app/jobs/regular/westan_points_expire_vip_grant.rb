# frozen_string_literal: true

module Jobs
  class WestanPointsExpireVipGrant < ::Jobs::Base
    def execute(args)
      return unless SiteSetting.westan_points_enabled

      ::WestanPoints::VipAccessService.expire_due_for!(
        user_id: args[:user_id],
        group_id: args[:group_id]
      )
    end
  end
end
