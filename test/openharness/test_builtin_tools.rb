# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

module Openharness
  module Rb
    module Tools
      module Builtin
        # Helper to build a ToolExecutionContext pointing at a temp directory
        def self.make_context(cwd)
          Models::ToolExecutionContext.new(
            cwd: cwd,
            session_id: "test-session",
            event_emitter: proc {}
          )
        end

        # 5.14.1 Test ReadFileTool reads file content, returns error for missing file
        class TestReadFileTool < Minitest::Test
          # **Validates: Requirements 13.1, 13.2**

          def setup
            @tool = ReadFileTool.new
            @tmpdir = Dir.mktmpdir
            @context = Builtin.make_context(@tmpdir)
          end

          def teardown
            FileUtils.remove_entry(@tmpdir)
          end

          def test_reads_existing_file_content
            File.write(File.join(@tmpdir, "hello.txt"), "Hello, world!")
            result = @tool.call({ path: "hello.txt" }, @context)

            assert_instance_of Models::ToolResult, result
            refute result.is_error
            assert_equal "Hello, world!", result.text
          end

          def test_returns_error_for_missing_file
            result = @tool.call({ path: "nonexistent.txt" }, @context)

            assert_instance_of Models::ToolResult, result
            assert result.is_error
            assert_includes result.text, "not found"
          end
        end

        # 5.14.2 Test WriteToFileTool creates file and parent directories
        class TestWriteToFileTool < Minitest::Test
          # **Validates: Requirements 13.3**

          def setup
            @tool = WriteToFileTool.new
            @tmpdir = Dir.mktmpdir
            @context = Builtin.make_context(@tmpdir)
          end

          def teardown
            FileUtils.remove_entry(@tmpdir)
          end

          def test_creates_file_with_nested_directories
            result = @tool.call(
              { path: "a/b/c/deep.txt", content: "nested content" },
              @context
            )

            refute result.is_error
            full_path = File.join(@tmpdir, "a", "b", "c", "deep.txt")
            assert File.exist?(full_path), "Expected file to be created at nested path"
            assert_equal "nested content", File.read(full_path)
          end
        end

        # 5.14.3 Test EditFileTool applies replacement, errors on not-found or ambiguous match
        class TestEditFileTool < Minitest::Test
          # **Validates: Requirements 13.4**

          def setup
            @tool = EditFileTool.new
            @tmpdir = Dir.mktmpdir
            @context = Builtin.make_context(@tmpdir)
          end

          def teardown
            FileUtils.remove_entry(@tmpdir)
          end

          def test_applies_unique_replacement
            File.write(File.join(@tmpdir, "code.rb"), "def hello\n  puts 'hi'\nend\n")
            result = @tool.call(
              { path: "code.rb", old_str: "puts 'hi'", new_str: "puts 'hello'" },
              @context
            )

            refute result.is_error
            content = File.read(File.join(@tmpdir, "code.rb"))
            assert_includes content, "puts 'hello'"
            refute_includes content, "puts 'hi'"
          end

          def test_errors_on_not_found_old_str
            File.write(File.join(@tmpdir, "code.rb"), "def hello\nend\n")
            result = @tool.call(
              { path: "code.rb", old_str: "nonexistent text", new_str: "replacement" },
              @context
            )

            assert result.is_error
            assert_includes result.text, "not found"
          end

          def test_errors_on_ambiguous_match
            File.write(File.join(@tmpdir, "code.rb"), "aaa\naaa\n")
            result = @tool.call(
              { path: "code.rb", old_str: "aaa", new_str: "bbb" },
              @context
            )

            assert result.is_error
            assert_includes result.text, "matches"
          end
        end

        # 5.14.4 Test GrepTool returns matching lines with paths and line numbers
        class TestGrepTool < Minitest::Test
          # **Validates: Requirements 13.5**

          def setup
            @tool = GrepTool.new
            @tmpdir = Dir.mktmpdir
            @context = Builtin.make_context(@tmpdir)
          end

          def teardown
            FileUtils.remove_entry(@tmpdir)
          end

          def test_returns_matching_lines_with_file_and_line_number
            File.write(File.join(@tmpdir, "a.rb"), "# TODO: fix this\nok line\n# TODO: another\n")
            File.write(File.join(@tmpdir, "b.rb"), "no match here\n")

            result = @tool.call({ pattern: "TODO", glob: "**/*.rb" }, @context)

            refute result.is_error
            lines = result.text.split("\n")
            assert_equal 2, lines.length

            # Each line should be file:line_number:content
            lines.each do |line|
              parts = line.split(":", 3)
              assert_equal 3, parts.length, "Expected file:line:content format, got: #{line}"
              assert_match(/\A\d+\z/, parts[1], "Expected line number")
            end
          end
        end

        # 5.14.5 Test GlobTool returns matching file paths
        class TestGlobTool < Minitest::Test
          # **Validates: Requirements 13.6**

          def setup
            @tool = GlobTool.new
            @tmpdir = Dir.mktmpdir
            @context = Builtin.make_context(@tmpdir)
          end

          def teardown
            FileUtils.remove_entry(@tmpdir)
          end

          def test_returns_matching_file_paths
            File.write(File.join(@tmpdir, "app.rb"), "")
            File.write(File.join(@tmpdir, "lib.rb"), "")
            File.write(File.join(@tmpdir, "readme.md"), "")
            File.write(File.join(@tmpdir, "data.json"), "")

            result = @tool.call({ pattern: "*.rb" }, @context)

            refute result.is_error
            paths = result.text.split("\n").sort
            assert_equal 2, paths.length
            assert_includes paths, "app.rb"
            assert_includes paths, "lib.rb"
          end
        end

        # 5.14.6 Test BashTool executes command, respects timeout
        class TestBashTool < Minitest::Test
          # **Validates: Requirements 14.1, 14.2, 14.4**

          def setup
            @tool = BashTool.new
            @tmpdir = Dir.mktmpdir
            @context = Builtin.make_context(@tmpdir)
          end

          def teardown
            FileUtils.remove_entry(@tmpdir)
          end

          def test_executes_command_and_returns_output
            result = @tool.call({ command: "echo hello" }, @context)

            refute result.is_error
            assert_equal "hello", result.text
          end

          def test_respects_timeout
            result = @tool.call({ command: "sleep 10", timeout: 1 }, @context)

            assert result.is_error
            assert_includes result.text, "timed out"
          end
        end
      end
    end
  end
end
