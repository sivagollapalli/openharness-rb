# frozen_string_literal: true

require "dry-struct"
require_relative "../types"
require_relative "content_block"

module Openharness
  module Rb
    module Models
      class ConversationMessage < Dry::Struct
        attribute :role, Types::String.enum("user", "assistant", "system")
        attribute :content_blocks, Types::Array.of(ContentBlock)

        def to_h
          {
            "role" => role,
            "content_blocks" => content_blocks.map do |block|
              {
                "type" => block.type,
                "content" => block.content.transform_keys(&:to_s)
              }
            end
          }
        end

        def self.from_h(hash)
          role = hash["role"] || hash[:role]
          raw_blocks = hash["content_blocks"] || hash[:content_blocks] || []

          blocks = raw_blocks.map do |b|
            type = b["type"] || b[:type]
            content = b["content"] || b[:content]
            content_sym = content.is_a?(Hash) ? content.transform_keys(&:to_sym) : content
            ContentBlock.new(type: type, content: content_sym)
          end

          new(role: role, content_blocks: blocks)
        end
      end
    end
  end
end
