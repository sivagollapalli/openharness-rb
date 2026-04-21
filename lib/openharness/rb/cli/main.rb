# frozen_string_literal: true

require "thor"

module Openharness
  module Rb
    module Cli
      class Main < Thor
        desc "start", "Start an interactive agent session"
        option :provider, type: :string, desc: "LLM provider name"
        option :model, type: :string, desc: "Model identifier"
        option :api_key, type: :string, desc: "API key for the provider"
        option :cwd, type: :string, default: Dir.pwd, desc: "Working directory"
        def start
          settings = load_settings(options)
          session = InteractiveSession.new(settings: settings)
          session.run
        end

        desc "setup", "Configure OpenHarness"
        def setup
          SetupWizard.new.run
        end

        default_command :start

        private

        def load_settings(opts)
          attrs = {}
          attrs[:api_key] = opts[:api_key] if opts[:api_key]
          attrs[:model] = opts[:model] if opts[:model]
          Config::Settings.new(**attrs)
        end
      end
    end
  end
end
