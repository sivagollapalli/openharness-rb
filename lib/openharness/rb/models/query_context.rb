# frozen_string_literal: true

require "dry-struct"
require_relative "../types"

module Openharness
  module Rb
    module Models
      class QueryContext < Dry::Struct
        attribute :cwd, Types::String.default { Dir.pwd }
        attribute :max_turns, Types::Integer.default(10)
        attribute? :permission_prompt, Types::Any.optional
        attribute? :ask_user_prompt, Types::Any.optional
      end
    end
  end
end
