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

      class TurnStarted < StreamEvent
        attribute :turn_number, Types::Integer
        attribute :max_turns, Types::Integer
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

      class SkillLoaded < StreamEvent
        attribute :skill_name, Types::String
        attribute :description, Types::String
        attribute :content_length, Types::Integer
      end

      class MemorySaved < StreamEvent
        attribute :memory_name, Types::String
        attribute :memory_type, Types::String.optional
        attribute :description, Types::String
      end

      class ClarificationNeeded < StreamEvent
        attribute :question, Types::String
      end

      class ContextSummarized < StreamEvent
        attribute :usage_ratio, Types::Float
        attribute :messages_before, Types::Integer
        attribute :messages_after, Types::Integer
      end

      class ContextCompacted < StreamEvent
        attribute :usage_ratio, Types::Float
        attribute :messages_before, Types::Integer
        attribute :messages_after, Types::Integer
      end
    end
  end
end
