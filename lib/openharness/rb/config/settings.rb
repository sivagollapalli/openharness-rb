# frozen_string_literal: true

require "yaml"
require "json"
require "dry-struct"

module Openharness
  module Rb
    module Config
      class Settings < Dry::Struct
        VALID_PERMISSION_MODES = %i[default plan full_auto].freeze

        attribute :permission_mode, Types::Symbol.default(:default)
        attribute :denied_tools, Types::Array.of(Types::String).default([].freeze)
        attribute :allowed_tools, Types::Array.of(Types::String).default([].freeze)
        attribute :path_rules, Types::Array.default([].freeze)
        attribute :denied_commands, Types::Array.default([].freeze)
        attribute :api_key, Types::String.optional.default(nil)
        attribute :base_url, Types::String.optional.default(nil)
        attribute :model, Types::String.optional.default(nil)
        attribute :max_turns, Types::Integer.default(10)
        attribute :context_window_threshold, Types::Integer.default(100_000)
        attribute :summarize_threshold, Types::Float.default(0.25)
        attribute :compact_threshold, Types::Float.default(0.50)
        attribute :context_strategy, Types::Any.optional.default(nil)
        attribute :mcp_servers, Types::Array.default([].freeze)

        def self.load_file(path)
          ext = File.extname(path)
          data = case ext
                 when ".yml", ".yaml"
                   YAML.safe_load(File.read(path), permitted_classes: [Symbol], symbolize_names: true) || {}
                 when ".json"
                   JSON.parse(File.read(path), symbolize_names: true)
                 else
                   raise ConfigurationError, "Unsupported config format: #{ext}"
                 end
          # Convert string permission_mode to symbol if needed
          if data[:permission_mode].is_a?(String)
            data[:permission_mode] = data[:permission_mode].to_sym
          end
          settings = new(**data)
          validate_settings!(settings)
          settings
        rescue Dry::Struct::Error => e
          raise ConfigurationError, "Invalid configuration: #{e.message}"
        end

        def to_h
          super
        end

        def self.validate_settings!(settings)
          unless VALID_PERMISSION_MODES.include?(settings.permission_mode)
            raise ConfigurationError,
                  "Invalid permission_mode: #{settings.permission_mode}. Must be one of: #{VALID_PERMISSION_MODES.join(', ')}"
          end

          unless settings.max_turns.positive?
            raise ConfigurationError, "max_turns must be positive, got: #{settings.max_turns}"
          end

          unless settings.context_window_threshold.positive?
            raise ConfigurationError,
                  "context_window_threshold must be positive, got: #{settings.context_window_threshold}"
          end
        end
      end
    end
  end
end
