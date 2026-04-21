# frozen_string_literal: true

require "yaml"

module Openharness
  module Rb
    module Cli
      class SetupWizard
        PROVIDERS = %w[openai anthropic gemini].freeze
        CONFIG_DIR = File.expand_path("~/.openharness")
        CONFIG_FILE = File.join(CONFIG_DIR, "config.yml")

        def initialize(input: $stdin, output: $stdout)
          @input = input
          @output = output
        end

        def run
          @output.puts "OpenHarness Setup"
          @output.puts "=" * 40

          provider = prompt_provider
          api_key = prompt_api_key(provider)

          save_config(provider: provider, api_key: api_key)
          @output.puts "\nConfiguration saved to #{CONFIG_FILE}"
        end

        private

        def prompt_provider
          @output.puts "\nSelect a provider:"
          PROVIDERS.each_with_index { |p, i| @output.puts "  #{i + 1}. #{p}" }
          @output.print "Choice [1]: "
          choice = @input.gets&.chomp&.strip
          idx = (choice.nil? || choice.empty?) ? 0 : choice.to_i - 1
          idx = 0 if idx < 0 || idx >= PROVIDERS.length
          PROVIDERS[idx]
        end

        def prompt_api_key(provider)
          @output.print "\nEnter your #{provider} API key: "
          @input.gets&.chomp&.strip || ""
        end

        def save_config(provider:, api_key:)
          Dir.mkdir(CONFIG_DIR) unless Dir.exist?(CONFIG_DIR)
          config = { "provider" => provider, "api_key" => api_key }
          File.write(CONFIG_FILE, YAML.dump(config))
        end
      end
    end
  end
end
