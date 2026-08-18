# frozen_string_literal: true

module WestanPoints
  class Engine < ::Rails::Engine
    engine_name WestanPoints::PLUGIN_NAME
    isolate_namespace WestanPoints
    config.autoload_paths << File.join(config.root, "lib")
  end
end
