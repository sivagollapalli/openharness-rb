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
        option :resume, type: :string, desc: "Resume from a session file (UUID or path to .json)"
        def start
          settings = load_settings(options)
          resume_path = resolve_resume_path(options[:resume])
          session = InteractiveSession.new(settings: settings, resume_from: resume_path)
          session.run
        end

        desc "setup", "Configure OpenHarness"
        def setup
          SetupWizard.new.run
        end

        desc "export", "Export the last session"
        def export
          sessions_dir = File.join(Dir.pwd, ".openharness", "sessions")
          unless Dir.exist?(sessions_dir)
            puts "No sessions found in #{sessions_dir}"
            return
          end

          files = Dir.glob(File.join(sessions_dir, "*.json")).sort_by { |f| File.mtime(f) }
          if files.empty?
            puts "No session files found."
          else
            puts "Latest session: #{files.last}"
          end
        end

        default_command :start

        private

        def load_settings(opts)
          attrs = {}
          attrs[:api_key] = opts[:api_key] if opts[:api_key]
          attrs[:model] = opts[:model] if opts[:model]
          Config::Settings.new(**attrs)
        end

        # Resolve a resume argument to a file path.
        # Accepts a full path, a filename, or just a UUID.
        def resolve_resume_path(resume_arg)
          return nil unless resume_arg

          # If it's already a full path that exists, use it
          return resume_arg if File.exist?(resume_arg)

          # Try as a UUID — look in the project sessions directory
          sessions_dir = File.join(Dir.pwd, ".openharness", "sessions")
          uuid_path = File.join(sessions_dir, "#{resume_arg}.json")
          return uuid_path if File.exist?(uuid_path)

          # Try without .json extension
          bare_path = File.join(sessions_dir, resume_arg)
          return bare_path if File.exist?(bare_path)

          # Return as-is and let SessionStorage.load raise the error
          resume_arg
        end
      end
    end
  end
end
