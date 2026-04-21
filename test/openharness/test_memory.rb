# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "yaml"

module Openharness
  module Rb
    # ---------------------------------------------------------------
    # 10.4.1 [PBT] Property: Tokenizer lowercase invariant
    # **Validates: Requirements 33.3**
    # Property 10: All tokens produced by the tokenizer are lowercase
    # ---------------------------------------------------------------
    class TestTokenizerLowercaseInvariant < Minitest::Test
      def setup
        @tokenizer = Memory::Tokenizer.new
      end

      def test_all_tokens_are_lowercase
        100.times do |i|
          text = generate_random_text(i)
          tokens = @tokenizer.tokenize(text)
          tokens.each do |token|
            assert_equal token.downcase, token,
              "Iteration #{i}: token '#{token}' from text '#{text}' is not lowercase"
          end
        end
      end

      private

      def generate_random_text(seed)
        rng = Random.new(seed)
        # Mix ASCII words, uppercase, CJK characters, and punctuation
        ascii_words = %w[Hello WORLD FooBar TEST Ruby OpenHarness MEMORY Search Query TOKEN]
        cjk_chars = %w[你 好 世 界 记 忆 搜 索 测 试 代 码 文 件]
        parts = []
        rng.rand(3..8).times do
          case rng.rand(3)
          when 0
            parts << ascii_words[rng.rand(ascii_words.length)]
          when 1
            # Random CJK string
            len = rng.rand(1..5)
            parts << Array.new(len) { cjk_chars[rng.rand(cjk_chars.length)] }.join
          when 2
            # Mixed with punctuation
            parts << "#{ascii_words[rng.rand(ascii_words.length)]}!@##{cjk_chars[rng.rand(cjk_chars.length)]}"
          end
        end
        parts.join(" ")
      end
    end

    # ---------------------------------------------------------------
    # 10.4.2 [PBT] Property: Tokenizer CJK segmentation
    # **Validates: Requirements 33.2**
    # Property 11: Han-only strings produce single-char tokens
    # ---------------------------------------------------------------
    class TestTokenizerCjkSegmentation < Minitest::Test
      def setup
        @tokenizer = Memory::Tokenizer.new
      end

      def test_han_only_strings_produce_single_char_tokens
        100.times do |i|
          text = generate_han_string(i)
          tokens = @tokenizer.tokenize(text)
          tokens.each do |token|
            assert_equal 1, token.length,
              "Iteration #{i}: token '#{token}' from Han text '#{text}' should be single char"
          end
          # Also verify we get the right number of tokens (one per Han char)
          expected_count = text.chars.count { |c| c.match?(/\p{Han}/) }
          assert_equal expected_count, tokens.length,
            "Iteration #{i}: expected #{expected_count} tokens from '#{text}', got #{tokens.length}"
        end
      end

      private

      def generate_han_string(seed)
        rng = Random.new(seed)
        cjk_chars = %w[你 好 世 界 记 忆 搜 索 测 试 代 码 文 件 系 统 内 存 查 找]
        len = rng.rand(1..10)
        Array.new(len) { cjk_chars[rng.rand(cjk_chars.length)] }.join
      end
    end

    # ---------------------------------------------------------------
    # 10.4.3 Test MemorySystem scan_memory_files returns sorted by
    #         modification time (most recent first)
    # **Validates: Requirements 32.4**
    # ---------------------------------------------------------------
    class TestMemorySystemScanSorted < Minitest::Test
      def test_scan_memory_files_sorted_by_modification_time
        Dir.mktmpdir do |project_dir|
          memory_dir = File.join(project_dir, ".openharness", "memory")
          FileUtils.mkdir_p(memory_dir)

          # Create files with staggered modification times
          file_a = File.join(memory_dir, "old.md")
          File.write(file_a, "Old memory content")
          FileUtils.touch(file_a, mtime: Time.now - 300)

          file_b = File.join(memory_dir, "mid.md")
          File.write(file_b, "Mid memory content")
          FileUtils.touch(file_b, mtime: Time.now - 100)

          file_c = File.join(memory_dir, "new.md")
          File.write(file_c, "New memory content")
          FileUtils.touch(file_c, mtime: Time.now)

          system = Memory::MemorySystem.new(project_dir: project_dir)
          headers = system.scan_memory_files

          assert_equal 3, headers.length
          assert_equal "new", headers[0].name
          assert_equal "mid", headers[1].name
          assert_equal "old", headers[2].name

          # Verify descending order
          headers.each_cons(2) do |a, b|
            assert a.modified_at >= b.modified_at,
              "Expected #{a.name} (#{a.modified_at}) >= #{b.name} (#{b.modified_at})"
          end
        end
      end

      def test_scan_excludes_memory_index_file
        Dir.mktmpdir do |project_dir|
          memory_dir = File.join(project_dir, ".openharness", "memory")
          FileUtils.mkdir_p(memory_dir)

          File.write(File.join(memory_dir, "MEMORY.md"), "# Index")
          File.write(File.join(memory_dir, "notes.md"), "Some notes")

          system = Memory::MemorySystem.new(project_dir: project_dir)
          headers = system.scan_memory_files

          assert_equal 1, headers.length
          assert_equal "notes", headers[0].name
        end
      end

      def test_scan_returns_empty_for_missing_directory
        system = Memory::MemorySystem.new(project_dir: "/tmp/nonexistent_#{rand(100_000)}")
        assert_equal [], system.scan_memory_files
      end
    end

    # ---------------------------------------------------------------
    # 10.4.4 Test MemorySystem find_relevant_memories scores
    #         metadata 2x vs body
    # **Validates: Requirements 32.5**
    # ---------------------------------------------------------------
    class TestMemorySystemRelevanceScoring < Minitest::Test
      def test_metadata_weighted_2x_over_body
        Dir.mktmpdir do |project_dir|
          memory_dir = File.join(project_dir, ".openharness", "memory")
          FileUtils.mkdir_p(memory_dir)

          # File A: query term "ruby" in metadata only
          File.write(File.join(memory_dir, "meta-match.md"), <<~MD)
            ---
            name: ruby programming
            description: ruby language tips
            ---
            Some generic content about coding.
          MD

          # File B: query term "ruby" in body only
          File.write(File.join(memory_dir, "body-match.md"), <<~MD)
            ---
            name: general notes
            description: miscellaneous tips
            ---
            Ruby is a great programming language. Ruby has blocks and procs.
          MD

          system = Memory::MemorySystem.new(project_dir: project_dir)
          results = system.find_relevant_memories("ruby")

          assert_equal 2, results.length

          meta_result = results.find { |r| r[:header].name == "ruby programming" }
          body_result = results.find { |r| r[:header].name == "general notes" }

          refute_nil meta_result, "Expected to find meta-match result"
          refute_nil body_result, "Expected to find body-match result"

          # The metadata match should score higher because metadata is weighted 2x
          assert meta_result[:score] > body_result[:score],
            "Metadata match (#{meta_result[:score]}) should score higher than body match (#{body_result[:score]})"
        end
      end
    end

    # ---------------------------------------------------------------
    # 10.4.5 Test MemorySystem parses YAML frontmatter into
    #         MemoryHeader
    # **Validates: Requirements 32.3**
    # ---------------------------------------------------------------
    class TestMemorySystemFrontmatterParsing < Minitest::Test
      def test_parses_yaml_frontmatter_into_memory_header
        Dir.mktmpdir do |project_dir|
          memory_dir = File.join(project_dir, ".openharness", "memory")
          FileUtils.mkdir_p(memory_dir)

          File.write(File.join(memory_dir, "architecture.md"), <<~MD)
            ---
            name: system-architecture
            description: Overview of the system architecture
            type: reference
            ---
            # Architecture

            The system uses a layered architecture.
          MD

          system = Memory::MemorySystem.new(project_dir: project_dir)
          headers = system.scan_memory_files

          assert_equal 1, headers.length
          header = headers.first

          assert_equal "system-architecture", header.name
          assert_equal "Overview of the system architecture", header.description
          assert_equal "reference", header.type
          assert_instance_of Time, header.modified_at
          assert header.path.end_with?("architecture.md")
        end
      end

      def test_falls_back_to_filename_without_frontmatter
        Dir.mktmpdir do |project_dir|
          memory_dir = File.join(project_dir, ".openharness", "memory")
          FileUtils.mkdir_p(memory_dir)

          File.write(File.join(memory_dir, "quick-notes.md"), <<~MD)
            # Quick Notes

            Just some plain text without frontmatter.
          MD

          system = Memory::MemorySystem.new(project_dir: project_dir)
          headers = system.scan_memory_files

          assert_equal 1, headers.length
          header = headers.first

          assert_equal "quick-notes", header.name
          assert_nil header.description
          assert_nil header.type
        end
      end

      def test_frontmatter_with_missing_name_falls_back_to_filename
        Dir.mktmpdir do |project_dir|
          memory_dir = File.join(project_dir, ".openharness", "memory")
          FileUtils.mkdir_p(memory_dir)

          File.write(File.join(memory_dir, "partial.md"), <<~MD)
            ---
            description: Has description but no name
            type: note
            ---
            Content here.
          MD

          system = Memory::MemorySystem.new(project_dir: project_dir)
          headers = system.scan_memory_files

          header = headers.first
          assert_equal "partial", header.name
          assert_equal "Has description but no name", header.description
          assert_equal "note", header.type
        end
      end
    end
  end
end
