# frozen_string_literal: true

require "dry-struct"
require_relative "../types"

module Openharness
  module Rb
    module Permissions
      class PathRule < Dry::Struct
        attribute :pattern, Types::String
        attribute :action, Types::String.enum("allow", "deny")
      end
    end
  end
end
