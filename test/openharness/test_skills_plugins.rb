# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "json"
require "fileutils"

module Openharness
  module Rb
    # ---------------------------------------------------------------
    # 9.6.1 Test SkillRegistry parses YAML frontmatter skills
    # ---------------------------------------------------------------
    class TestSkillRegistryYamlFrontmatter < Minitest::Test
      # **Validates: Requirements 29.3**

      def test_parses_yaml_frontmatter_skill
        Dir.mktmpdir do |dir|
          skill_path = File.join(dir, "coding.md")
          File.write(skill_path, <<~MD)
            ---
            name: coding-best-practices
            description: Best practices for writing clean code
            ---
            ## Clean Code

            Always write tests first.
          MD

          registry = Skills::SkillRegistry.new
          registry.send(:load_from_directory, dir)

          skill = registry.get("coding-best-practices")
          assert_equal "coding-best-practices", skill.name
          assert_equal "Best practices for writing clean code", skill.description
          assert_includes skill.content, "## Clean Code"
          assert_includes skill.content, "Always write tests first."
        end
      end

      def test_parses_multiple_frontmatter_skills
        Dir.mktmpdir do |dir|
          File.write(File.join(dir, "a.md"), <<~MD)
            ---
            name: skill-a
            description: First skill
            ---
            Content A
          MD
          File.write(File.join(dir, "b.md"), <<~MD)
            ---
            name: skill-b
            description: Second skill
            ---
            Content B
          MD

          registry = Skills::SkillRegistry.new
          registry.send(:load_from_directory, dir)

          assert_includes registry.available_names, "skill-a"
          assert_includes registry.available_names, "skill-b"
        end
      end
    end

    # ---------------------------------------------------------------
    # 9.6.2 Test SkillRegistry falls back to H1/first-paragraph
    # ---------------------------------------------------------------
    class TestSkillRegistryH1Fallback < Minitest::Test
      # **Validates: Requirements 29.4**

      def test_derives_name_from_h1_heading
        Dir.mktmpdir do |dir|
          skill_path = File.join(dir, "debugging.md")
          File.write(skill_path, <<~MD)
            # Debugging Tips

            Useful techniques for debugging Ruby applications.

            ## Step 1
            Use pry or byebug.
          MD

          registry = Skills::SkillRegistry.new
          registry.send(:load_from_directory, dir)

          skill = registry.get("Debugging Tips")
          assert_equal "Debugging Tips", skill.name
          assert_equal "Useful techniques for debugging Ruby applications.", skill.description
        end
      end

      def test_falls_back_to_filename_when_no_h1
        Dir.mktmpdir do |dir|
          skill_path = File.join(dir, "misc-tips.md")
          File.write(skill_path, "Just some plain text content.\n")

          registry = Skills::SkillRegistry.new
          registry.send(:load_from_directory, dir)

          skill = registry.get("Just some plain text content.")
          assert_equal "Just some plain text content.", skill.name
        end
      end
    end

    # ---------------------------------------------------------------
    # 9.6.3 Test SkillRegistry raises SkillNotFoundError
    # ---------------------------------------------------------------
    class TestSkillRegistryNotFound < Minitest::Test
      # **Validates: Requirements 29.5**

      def test_raises_skill_not_found_error_for_unknown_skill
        registry = Skills::SkillRegistry.new
        assert_raises(SkillNotFoundError) { registry.get("nonexistent-skill") }
      end
    end

    # ---------------------------------------------------------------
    # 9.6.4 Test PluginLoader discovers plugins from directories
    # ---------------------------------------------------------------
    class TestPluginLoaderDiscovery < Minitest::Test
      # **Validates: Requirements 31.2, 31.3**

      def test_discovers_plugins_from_directory
        Dir.mktmpdir do |dir|
          # Create two plugin directories with valid manifests
          plugin_a = File.join(dir, "plugin-a")
          FileUtils.mkdir_p(plugin_a)
          File.write(File.join(plugin_a, "plugin.json"), JSON.generate(
            name: "plugin-a",
            version: "1.0.0",
            skills: ["skill-x"]
          ))

          plugin_b = File.join(dir, "plugin-b")
          FileUtils.mkdir_p(plugin_b)
          File.write(File.join(plugin_b, "plugin.json"), JSON.generate(
            name: "plugin-b",
            version: "2.0.0"
          ))

          loader = Plugins::PluginLoader.new
          plugins = loader.load_from_directory(dir)

          assert_equal 2, plugins.size
          names = plugins.map { |p| p.manifest.name }
          assert_includes names, "plugin-a"
          assert_includes names, "plugin-b"

          plugin_a_loaded = plugins.find { |p| p.manifest.name == "plugin-a" }
          assert_equal "1.0.0", plugin_a_loaded.manifest.version
          assert_equal ["skill-x"], plugin_a_loaded.manifest.skills
          assert_equal plugin_a, plugin_a_loaded.path
        end
      end

      def test_returns_empty_for_nonexistent_directory
        loader = Plugins::PluginLoader.new
        assert_equal [], loader.load_from_directory("/tmp/nonexistent_#{rand(100_000)}")
      end

      def test_skips_non_directory_entries
        Dir.mktmpdir do |dir|
          # Create a regular file (not a directory) — should be skipped
          File.write(File.join(dir, "not-a-plugin"), "just a file")

          loader = Plugins::PluginLoader.new
          plugins = loader.load_from_directory(dir)
          assert_empty plugins
        end
      end
    end

    # ---------------------------------------------------------------
    # 9.6.5 Test PluginLoader skips invalid plugin.json with warning
    # ---------------------------------------------------------------
    class TestPluginLoaderInvalidJson < Minitest::Test
      # **Validates: Requirements 31.4**

      def test_skips_plugin_with_invalid_json
        Dir.mktmpdir do |dir|
          bad_plugin = File.join(dir, "bad-plugin")
          FileUtils.mkdir_p(bad_plugin)
          File.write(File.join(bad_plugin, "plugin.json"), "{ not valid json !!!")

          loader = Plugins::PluginLoader.new

          # Capture stderr to verify warning is emitted
          warnings = StringIO.new
          original_stderr = $stderr
          $stderr = warnings

          plugins = loader.load_from_directory(dir)

          $stderr = original_stderr

          assert_empty plugins
          assert_includes warnings.string, "Skipping invalid plugin"
        end
      end

      def test_skips_plugin_with_missing_required_fields
        Dir.mktmpdir do |dir|
          bad_plugin = File.join(dir, "incomplete-plugin")
          FileUtils.mkdir_p(bad_plugin)
          # Missing required 'name' and 'version' fields
          File.write(File.join(bad_plugin, "plugin.json"), JSON.generate(
            skills: ["some-skill"]
          ))

          loader = Plugins::PluginLoader.new

          warnings = StringIO.new
          original_stderr = $stderr
          $stderr = warnings

          plugins = loader.load_from_directory(dir)

          $stderr = original_stderr

          assert_empty plugins
          assert_includes warnings.string, "Skipping invalid plugin"
        end
      end

      def test_valid_plugins_still_loaded_alongside_invalid
        Dir.mktmpdir do |dir|
          # Valid plugin
          good_plugin = File.join(dir, "good-plugin")
          FileUtils.mkdir_p(good_plugin)
          File.write(File.join(good_plugin, "plugin.json"), JSON.generate(
            name: "good-plugin",
            version: "1.0.0"
          ))

          # Invalid plugin
          bad_plugin = File.join(dir, "bad-plugin")
          FileUtils.mkdir_p(bad_plugin)
          File.write(File.join(bad_plugin, "plugin.json"), "not json")

          loader = Plugins::PluginLoader.new

          original_stderr = $stderr
          $stderr = StringIO.new

          plugins = loader.load_from_directory(dir)

          $stderr = original_stderr

          assert_equal 1, plugins.size
          assert_equal "good-plugin", plugins.first.manifest.name
        end
      end
    end
  end
end
