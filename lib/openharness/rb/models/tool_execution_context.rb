# frozen_string_literal: true

require "dry-struct"
require_relative "../types"

module Openharness
  module Rb
    module Models
      class ToolExecutionContext < Dry::Struct
        attribute :cwd, Types::String
        attribute :session_id, Types::String
        attribute :event_emitter, Types::Any
      end
    end
  end
end
