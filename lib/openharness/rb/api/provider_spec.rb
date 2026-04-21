# frozen_string_literal: true

require "dry-struct"
require_relative "../types"

module Openharness
  module Rb
    module Api
      class ProviderSpec < Dry::Struct
        attribute :name, Types::String
        attribute :base_url, Types::String.optional
        attribute :auth_type, Types::String.enum("api_key", "oauth")
        attribute :model_pattern, Types::String.optional
        attribute :default_model, Types::String
      end
    end
  end
end
