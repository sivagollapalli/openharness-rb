# frozen_string_literal: true

require "json"

module Openharness
  module Rb
    module Plugins
      class PluginLoader
        SEARCH_PATHS = [
          File.expand_path("~/.openharness/plugins"),
          ".openharness/plugins"
        ].freeze

        def load_all
          SEARCH_PATHS.flat_map { |dir| load_from_directory(dir) }.compact
        end

        def load_from_directory(dir)
          return [] unless Dir.exist?(dir)

          Dir.children(dir).filter_map do |name|
            plugin_dir = File.join(dir, name)
            next unless File.directory?(plugin_dir)

            manifest_path = File.join(plugin_dir, "plugin.json")
            next unless File.exist?(manifest_path)

            manifest = PluginManifest.new(
              **JSON.parse(File.read(manifest_path), symbolize_names: true)
            )
            LoadedPlugin.new(manifest: manifest, path: plugin_dir)
          rescue JSON::ParserError, Dry::Struct::Error => e
            warn "Skipping invalid plugin at #{plugin_dir}: #{e.message}"
            nil
          end
        end
      end
    end
  end
end
