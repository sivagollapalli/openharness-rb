# frozen_string_literal: true

require "dry-struct"
require_relative "../types"

module Openharness
  module Rb
    module Models
      class ContentBlock < Dry::Struct
        attribute :type, Types::String.enum("text", "image", "tool_use", "tool_result")
        attribute :content, Types::Hash
      end
    end
  end
end
