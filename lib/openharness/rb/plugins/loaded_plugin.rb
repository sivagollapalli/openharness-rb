# frozen_string_literal: true

module Openharness
  module Rb
    module Plugins
      class LoadedPlugin
        attr_reader :manifest, :path, :skill_definitions, :hook_definitions, :mcp_configs

        def initialize(manifest:, path:)
          @manifest = manifest
          @path = path
          @skill_definitions = []
          @hook_definitions = []
          @mcp_configs = []
        end
      end
    end
  end
end
