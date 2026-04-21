# frozen_string_literal: true

require "dry-struct"
require_relative "../types"

module Openharness
  module Rb
    module Models
      class ToolResult < Dry::Struct
        attribute :text, Types::String
        attribute :is_error, Types::Bool.default(false)
      end
    end
  end
end
