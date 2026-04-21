# frozen_string_literal: true

require "dry-struct"
require_relative "../types"
require_relative "tool_result"

module Openharness
  module Rb
    module Models
      class StreamEvent < Dry::Struct; end

      class AssistantTextDelta < StreamEvent
        attribute :text, Types::String
      end

      class ToolExecutionStarted < StreamEvent
        attribute :tool_name, Types::String
        attribute :tool_use_id, Types::String
      end

      class ToolExecutionCompleted < StreamEvent
        attribute :tool_use_id, Types::String
        attribute :result, ToolResult
      end

      class AssistantTurnComplete < StreamEvent
        attribute :stop_reason, Types::String
      end

      class ErrorOccurred < StreamEvent
        attribute :error, Types::Any
      end
    end
  end
end
