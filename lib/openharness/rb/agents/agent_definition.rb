# frozen_string_literal: true

require "dry-struct"

module Openharness
  module Rb
    module Agents
      class AgentDefinition < Dry::Struct
        attribute :name, Types::String
        attribute :role, Types::String
        attribute :capabilities, Types::Array.of(Types::String).default([].freeze)
        attribute :tool_access, Types::Array.of(Types::String).default([].freeze)
      end
    end
  end
end
