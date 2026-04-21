# frozen_string_literal: true

module Openharness
  module Rb
    module Memory
      class Tokenizer
        # Multi-language tokenizer for memory search scoring.
        # Splits ASCII words on whitespace/punctuation boundaries and
        # segments Han ideographs into individual characters.
        HAN_RANGE = /\p{Han}/

        def tokenize(text)
          tokens = []
          text.scan(/[\p{Han}]|[a-zA-Z0-9]+/) do |match|
            tokens << match.downcase
          end
          tokens
        end
      end
    end
  end
end
