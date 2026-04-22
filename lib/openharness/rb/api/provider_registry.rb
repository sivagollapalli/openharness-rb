# frozen_string_literal: true

require_relative "provider_spec"

module Openharness
  module Rb
    module Api
      class ProviderRegistry
        PROVIDERS = {
          "openai" => { prefix: "sk-", default_model: "gpt-4o" },
          "anthropic" => { prefix: "sk-ant-", default_model: "claude-sonnet-4-20250514" },
          "gemini" => { prefix: "AI", default_model: "gemini-2.0-flash" },
          "openroute" => { prefix: "sk-or-v1", default_model: "openai/gpt-oss-120b" }
        }.freeze

        def initialize
          @custom_providers = {}
        end

        def register(name, spec)
          @custom_providers[name] = spec
        end

        def detect_provider(api_key:, base_url: nil)
          # Check custom providers first
          @custom_providers.each do |name, spec|
            if matches_provider?(api_key, base_url, spec)
              return spec
            end
          end

          # Then check built-in providers (sorted by prefix length descending for most-specific match)
          sorted_providers = PROVIDERS.sort_by { |_, info| -info[:prefix].length }
          sorted_providers.each do |name, info|
            if api_key.start_with?(info[:prefix])
              return ProviderSpec.new(
                name: name,
                base_url: base_url,
                auth_type: "api_key",
                model_pattern: nil,
                default_model: info[:default_model]
              )
            end
          end

          raise UnknownProviderError, "Cannot detect provider for key prefix: #{api_key[0..5]}..."
        end

        private

        def matches_provider?(api_key, base_url, spec)
          if spec.model_pattern && api_key
            return true if api_key.match?(Regexp.new(spec.model_pattern))
          end

          if spec.base_url && base_url
            return true if base_url.include?(spec.base_url)
          end

          false
        end
      end
    end
  end
end
