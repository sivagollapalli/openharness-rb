# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "yaml"
require "json"

module Openharness
  module Rb
    module Config
      # **Validates: Requirements 39.4**
      # Property 8: Settings round-trip — Settings.new(**settings.to_h) == settings
      class TestSettingsRoundTrip < Minitest::Test
        VALID_MODES = %i[default plan full_auto].freeze

        def random_string
          chars = ("a".."z").to_a
          (1..rand(3..10)).map { chars.sample }.join
        end

        def random_settings
          Settings.new(
            permission_mode: VALID_MODES.sample,
            denied_tools: Array.new(rand(0..3)) { random_string },
            allowed_tools: Array.new(rand(0..3)) { random_string },
            path_rules: Array.new(rand(0..2)) { random_string },
            denied_commands: Array.new(rand(0..2)) { random_string },
            api_key: [nil, random_string].sample,
            base_url: [nil, "https://#{random_string}.example.com"].sample,
            model: [nil, "gpt-#{rand(1..4)}"].sample,
            max_turns: rand(1..100),
            context_window_threshold: rand(1000..500_000)
          )
        end

        def test_round_trip_property
          100.times do |i|
            settings = random_settings
            reconstructed = Settings.new(**settings.to_h)

            assert_equal settings, reconstructed,
                         "Iteration #{i}: Settings round-trip failed for #{settings.to_h.inspect}"
          end
        end
      end

      # Test Settings.load_file from YAML
      class TestSettingsLoadYaml < Minitest::Test
        def setup
          @tmpdir = Dir.mktmpdir("settings_test")
        end

        def teardown
          FileUtils.rm_rf(@tmpdir)
        end

        def test_load_yaml_with_all_fields
          yaml_path = File.join(@tmpdir, "config.yml")
          config = {
            "permission_mode" => "plan",
            "denied_tools" => ["bash"],
            "allowed_tools" => ["read_file"],
            "path_rules" => [],
            "denied_commands" => ["rm -rf /"],
            "api_key" => "sk-test-key",
            "base_url" => "https://api.example.com",
            "model" => "gpt-4",
            "max_turns" => 20,
            "context_window_threshold" => 50_000
          }
          File.write(yaml_path, config.to_yaml)

          settings = Settings.load_file(yaml_path)
          assert_equal :plan, settings.permission_mode
          assert_equal ["bash"], settings.denied_tools
          assert_equal ["read_file"], settings.allowed_tools
          assert_equal "sk-test-key", settings.api_key
          assert_equal 20, settings.max_turns
          assert_equal 50_000, settings.context_window_threshold
        end

        def test_load_yaml_with_defaults
          yaml_path = File.join(@tmpdir, "minimal.yaml")
          File.write(yaml_path, {}.to_yaml)

          settings = Settings.load_file(yaml_path)
          assert_equal :default, settings.permission_mode
          assert_equal [], settings.denied_tools
          assert_equal 10, settings.max_turns
          assert_equal 100_000, settings.context_window_threshold
        end

        def test_load_json
          json_path = File.join(@tmpdir, "config.json")
          config = { "max_turns" => 15, "model" => "claude-3" }
          File.write(json_path, JSON.generate(config))

          settings = Settings.load_file(json_path)
          assert_equal 15, settings.max_turns
          assert_equal "claude-3", settings.model
        end
      end

      # Test Settings.load_file raises ConfigurationError for invalid values
      class TestSettingsLoadInvalid < Minitest::Test
        def setup
          @tmpdir = Dir.mktmpdir("settings_test")
        end

        def teardown
          FileUtils.rm_rf(@tmpdir)
        end

        def test_unsupported_format_raises
          txt_path = File.join(@tmpdir, "config.txt")
          File.write(txt_path, "some content")

          assert_raises(ConfigurationError) do
            Settings.load_file(txt_path)
          end
        end

        def test_invalid_type_raises
          yaml_path = File.join(@tmpdir, "bad.yml")
          File.write(yaml_path, { "max_turns" => "not_a_number" }.to_yaml)

          assert_raises(ConfigurationError) do
            Settings.load_file(yaml_path)
          end
        end

        def test_invalid_permission_mode_raises
          yaml_path = File.join(@tmpdir, "bad_mode.yml")
          File.write(yaml_path, { "permission_mode" => "invalid_mode" }.to_yaml)

          assert_raises(ConfigurationError) do
            Settings.load_file(yaml_path)
          end
        end
      end
    end

    module Engine
      # Simple stub tool for testing (avoids mock counting issues)
      class StubTool
        attr_reader :name, :description, :input_schema

        def initialize(name:, description:, input_schema: {})
          @name = name
          @description = description
          @input_schema = input_schema
        end
      end

      # Test SystemPromptBuilder includes tool schemas
      class TestSystemPromptBuilderToolSchemas < Minitest::Test
        def setup
          @registry = Tools::ToolRegistry.new
          tool = StubTool.new(
            name: "test_tool",
            description: "A test tool",
            input_schema: { type: "object", properties: { input: { type: "string" } } }
          )
          @registry.register(tool)
        end

        def test_build_includes_tool_schemas
          builder = SystemPromptBuilder.new(tool_registry: @registry)
          prompt = builder.build

          assert_includes prompt, "## Available Tools"
          assert_includes prompt, "test_tool"
          assert_includes prompt, "A test tool"
        end

        def test_build_includes_skills_when_present
          skill_registry = Minitest::Mock.new
          skill_registry.expect(:available_names, %w[coding debugging])

          builder = SystemPromptBuilder.new(tool_registry: @registry, skill_registry: skill_registry)
          prompt = builder.build

          assert_includes prompt, "## Available Skills"
          assert_includes prompt, "- coding"
          assert_includes prompt, "- debugging"
        end
      end

      # Test SystemPromptBuilder loads CLAUDE.md project context
      class TestSystemPromptBuilderProjectContext < Minitest::Test
        def setup
          @tmpdir = Dir.mktmpdir("prompt_test")
          @registry = Tools::ToolRegistry.new
          tool = StubTool.new(name: "t", description: "d")
          @registry.register(tool)
        end

        def teardown
          FileUtils.rm_rf(@tmpdir)
        end

        def test_loads_claude_md
          File.write(File.join(@tmpdir, "CLAUDE.md"), "# Project Rules\nBe helpful.")

          builder = SystemPromptBuilder.new(tool_registry: @registry, project_root: @tmpdir)
          prompt = builder.build

          assert_includes prompt, "## Project Context"
          assert_includes prompt, "# Project Rules"
          assert_includes prompt, "Be helpful."
        end

        def test_loads_openharness_context_md
          dir = File.join(@tmpdir, ".openharness")
          Dir.mkdir(dir)
          File.write(File.join(dir, "context.md"), "Custom context content")

          builder = SystemPromptBuilder.new(tool_registry: @registry, project_root: @tmpdir)
          prompt = builder.build

          assert_includes prompt, "## Project Context"
          assert_includes prompt, "Custom context content"
        end

        def test_prefers_claude_md_over_openharness_context
          File.write(File.join(@tmpdir, "CLAUDE.md"), "CLAUDE content")
          dir = File.join(@tmpdir, ".openharness")
          Dir.mkdir(dir)
          File.write(File.join(dir, "context.md"), "openharness content")

          builder = SystemPromptBuilder.new(tool_registry: @registry, project_root: @tmpdir)
          prompt = builder.build

          assert_includes prompt, "CLAUDE content"
          refute_includes prompt, "openharness content"
        end
      end

      # Test SystemPromptBuilder omits project context when no file exists
      class TestSystemPromptBuilderNoContext < Minitest::Test
        def setup
          @tmpdir = Dir.mktmpdir("prompt_test")
          @registry = Tools::ToolRegistry.new
          tool = StubTool.new(name: "t", description: "d")
          @registry.register(tool)
        end

        def teardown
          FileUtils.rm_rf(@tmpdir)
        end

        def test_omits_project_context_when_no_file
          builder = SystemPromptBuilder.new(tool_registry: @registry, project_root: @tmpdir)
          prompt = builder.build

          refute_includes prompt, "## Project Context"
          assert_includes prompt, "## Available Tools"
        end
      end
    end
  end
end
