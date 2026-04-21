# frozen_string_literal: true

require "listen"

module Openharness
  module Rb
    module Hooks
      class HookRegistry
        def initialize(config_paths: [])
          @hooks = Hash.new { |h, k| h[k] = [] }
          @config_paths = config_paths
          @listener = nil
        end

        def register(hook_def)
          @hooks[hook_def.event] << hook_def
        end

        def hooks_for(event, context_name: nil)
          @hooks[event].select do |h|
            h.matcher.nil? || File.fnmatch?(h.matcher, context_name || "")
          end
        end

        def start_watching!
          return if @config_paths.empty?

          dirs = @config_paths.map { |p| File.dirname(p) }.uniq
          @listener = Listen.to(*dirs) do |modified, _added, _removed|
            reload_configs(modified)
          end
          @listener.start
        end

        def stop_watching!
          @listener&.stop
          @listener = nil
        end

        private

        def reload_configs(modified_files)
          relevant = modified_files.select { |f| @config_paths.include?(f) }
          return if relevant.empty?

          relevant.each do |path|
            parse_and_register(path)
          rescue StandardError => e
            warn "Hook config reload failed for #{path}: #{e.message}"
          end
        end

        def parse_and_register(path)
          # Parse config file and re-register hooks.
          # Subclasses or configuration can override this.
          # Retains previous config on parse failure (rescue above).
        end
      end
    end
  end
end
