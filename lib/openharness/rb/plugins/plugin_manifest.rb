# frozen_string_literal: true

require "dry-struct"

module Openharness
  module Rb
    module Plugins
      class PluginManifest < Dry::Struct
        attribute :name, Types::String
        attribute :version, Types::String
        attribute :skills, Types::Array.of(Types::String).default([].freeze)
        attribute :commands, Types::Array.default([].freeze)
        attribute :agents, Types::Array.default([].freeze)
        attribute :hooks, Types::Array.default([].freeze)
        attribute :mcp_servers, Types::Array.default([].freeze)
      end
    end
  end
end
