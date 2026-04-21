# frozen_string_literal: true

require "test_helper"
require "openharness/rb/cli/main"
require "openharness/rb/cli/interactive_session"
require "openharness/rb/cli/setup_wizard"

module Openharness
  module Rb
    module Cli
      # 15.6.1 Test slash command dispatch
      class TestSlashCommandDispatch < Minitest::Test
        def setup
          @output = StringIO.new
          @settings = Config::Settings.new
        end

        def test_help_command
          input = StringIO.new("/help\n/exit\n")
          session = InteractiveSession.new(settings: @settings, input: input, output: @output)
          session.run
          assert_includes @output.string, "/help"
          assert_includes @output.string, "/exit"
          assert_includes @output.string, "/cost"
        end

        def test_memory_command
          input = StringIO.new("/memory\n/exit\n")
          session = InteractiveSession.new(settings: @settings, input: input, output: @output)
          session.run
          assert_includes @output.string, "Memory index"
        end

        def test_skill_command_without_args
          input = StringIO.new("/skill\n/exit\n")
          session = InteractiveSession.new(settings: @settings, input: input, output: @output)
          session.run
          assert_includes @output.string, "Usage: /skill <name>"
        end

        def test_skill_command_with_name
          input = StringIO.new("/skill ruby-basics\n/exit\n")
          session = InteractiveSession.new(settings: @settings, input: input, output: @output)
          session.run
          assert_includes @output.string, "Skill 'ruby-basics' requested."
        end

        def test_clear_command
          input = StringIO.new("/clear\n/exit\n")
          session = InteractiveSession.new(settings: @settings, input: input, output: @output)
          session.run
          assert_includes @output.string, "Conversation history cleared."
        end

        def test_cost_command
          input = StringIO.new("/cost\n/exit\n")
          session = InteractiveSession.new(settings: @settings, input: input, output: @output)
          session.run
          assert_includes @output.string, "input: 0"
          assert_includes @output.string, "output: 0"
          assert_includes @output.string, "Total cost:"
        end

        def test_exit_command
          input = StringIO.new("/exit\n")
          session = InteractiveSession.new(settings: @settings, input: input, output: @output)
          session.run
          assert_includes @output.string, "Goodbye!"
        end

        def test_unknown_command
          input = StringIO.new("/unknown\n/exit\n")
          session = InteractiveSession.new(settings: @settings, input: input, output: @output)
          session.run
          assert_includes @output.string, "Unknown command: /unknown"
        end
      end

      # 15.6.2 Test CLI accepts --provider, --model, --api-key flags
      class TestCliFlags < Minitest::Test
        def test_main_accepts_provider_option
          start_cmd = Main.commands["start"]
          options = start_cmd.options
          assert options.key?(:provider), "CLI should accept --provider"
          assert options.key?(:model), "CLI should accept --model"
          assert options.key?(:api_key), "CLI should accept --api-key"
          assert options.key?(:cwd), "CLI should accept --cwd"
        end

        def test_main_has_start_command
          commands = Main.commands
          assert commands.key?("start"), "CLI should have start command"
        end

        def test_main_has_setup_command
          commands = Main.commands
          assert commands.key?("setup"), "CLI should have setup command"
        end
      end
    end
  end
end
