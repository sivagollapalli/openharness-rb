# frozen_string_literal: true

require "dry-struct"
require_relative "../types"

module Openharness
  module Rb
    module Mcp
      class McpServerConfig < Dry::Struct
        attribute :name, Types::String
        attribute :transport, Types::String.enum("stdio", "http")
        attribute :command, Types::String.optional.default(nil)
        attribute :args, Types::Array.of(Types::String).default([].freeze)
        attribute :env, Types::Hash.default({}.freeze)
        attribute :url, Types::String.optional.default(nil)
        attribute :headers, Types::Hash.default({}.freeze)
      end
    end
  end
end
