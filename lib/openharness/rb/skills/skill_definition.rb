# frozen_string_literal: true

require "dry-struct"

module Openharness
  module Rb
    module Skills
      class SkillDefinition < Dry::Struct
        attribute :name, Types::String
        attribute :description, Types::String
        attribute :content, Types::String
      end
    end
  end
end
