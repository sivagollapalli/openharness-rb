# frozen_string_literal: true

require "dry-struct"
require_relative "../types"

module Openharness
  module Rb
    module Permissions
      class PermissionDecision < Dry::Struct
        attribute :status, Types::String.enum("allowed", "requires_confirmation", "denied")
        attribute :reason, Types::String.optional.meta(omittable: true)
      end
    end
  end
end
