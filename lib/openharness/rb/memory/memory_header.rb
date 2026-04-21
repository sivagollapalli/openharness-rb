# frozen_string_literal: true

require "dry-struct"

module Openharness
  module Rb
    module Memory
      class MemoryHeader < Dry::Struct
        attribute :name, Types::String
        attribute :description, Types::String.optional
        attribute :type, Types::String.optional
        attribute :path, Types::String
        attribute :modified_at, Types::Time
      end
    end
  end
end
