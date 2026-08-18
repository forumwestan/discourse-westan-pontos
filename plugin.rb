# frozen_string_literal: true

# name: discourse-westan-pontos
# about: Carteira de pontos e catálogo de benefícios para a comunidade Westan
# meta_topic_id: 0
# version: 0.3.1
# authors: Westan
# url: https://github.com/forumwestan/discourse-westan-pontos
# required_version: 3.2.0

enabled_site_setting :westan_points_enabled

register_asset "stylesheets/westan-points/points.scss"

register_svg_icon "gift"
register_svg_icon "clock-rotate-left"
register_svg_icon "circle-info"
register_svg_icon "gear"
register_svg_icon "check"
register_svg_icon "xmark"
register_svg_icon "plus"

module ::WestanPoints
  PLUGIN_NAME = "discourse-westan-pontos"
end

require_relative "lib/westan_points/engine"

after_initialize do
  require_relative "app/models/westan_points/wallet"
  require_relative "app/models/westan_points/transaction"
  require_relative "app/models/westan_points/reward"
  require_relative "app/models/westan_points/redemption"
  require_relative "app/models/westan_points/vip_grant"
  require_relative "app/services/westan_points/ledger"
  require_relative "app/services/westan_points/vip_access_service"
  require_relative "app/services/westan_points/redemption_service"
  require_relative "app/jobs/scheduled/westan_points_expire_points"
  require_relative "app/jobs/scheduled/westan_points_expire_vip_grants"
  require_relative "app/jobs/regular/westan_points_expire_vip_grant"
  require_relative "app/controllers/westan_points/points_controller"

  WestanPoints::Engine.routes.draw do
    get "/" => "points#index"
    post "/redeem" => "points#redeem"
    post "/admin/rewards" => "points#create_reward"
    patch "/admin/rewards/:id" => "points#update_reward"
    patch "/admin/redemptions/:id" => "points#update_redemption"
    post "/admin/adjust" => "points#adjust_balance"
  end

  Discourse::Application.routes.prepend do
    get "/westan/pontos" => "westan_points/points#index"
    post "/westan/pontos/redeem" => "westan_points/points#redeem"
    post "/westan/pontos/admin/rewards" => "westan_points/points#create_reward"
    patch "/westan/pontos/admin/rewards/:id" => "westan_points/points#update_reward"
    patch "/westan/pontos/admin/redemptions/:id" => "westan_points/points#update_redemption"
    post "/westan/pontos/admin/adjust" => "westan_points/points#adjust_balance"
  end

  Discourse::Application.routes.append do
    get "/pontos" => "list#latest"
    get "/pontos/*path" => "list#latest"
  end
end

on(:post_created) do |post|
  ::WestanPoints::Ledger.process_post(post, :created)
end

on(:post_destroyed) do |post|
  ::WestanPoints::Ledger.process_post(post, :destroyed)
end

on(:post_recovered) do |post|
  ::WestanPoints::Ledger.process_post(post, :recovered)
end
