# frozen_string_literal: true

require "dry-struct"
require_relative "../types"

module Openharness
  module Rb
    module Hooks
      class HookDefinition < Dry::Struct
        attribute :event, Types::Symbol
        attribute :matcher, Types::String.optional
        attribute :block_on_failure, Types::Bool.default(false)
      end

      class CommandHookDefinition < HookDefinition
        attribute :command, Types::String
      end

      class HttpHookDefinition < HookDefinition
        attribute :url, Types::String
        attribute :headers, Types::Hash.default({}.freeze)
      end

      class PromptHookDefinition < HookDefinition
        attribute :prompt_template, Types::String
      end
    end
  end
end
