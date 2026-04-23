# frozen_string_literal: true

require "yaml"

module Openharness
  module Rb
    module Memory
      class MemorySystem
        INDEX_FILE = "MEMORY.md"

        def initialize(project_dir: Dir.pwd)
          @memory_dir = get_project_memory_dir(project_dir)
          @tokenizer = Tokenizer.new
        end

        def scan_memory_files
          return [] unless Dir.exist?(@memory_dir)

          Dir.glob(File.join(@memory_dir, "*.md"))
            .reject { |f| File.basename(f) == INDEX_FILE }
            .map { |f| parse_memory_file(f) }
            .sort_by { |h| -h.modified_at.to_f }
        end

        def find_relevant_memories(query, limit: 5)
          query_tokens = @tokenizer.tokenize(query)
          headers = scan_memory_files

          scored = headers.map do |header|
            meta_score = score_tokens(query_tokens, @tokenizer.tokenize("#{header.name} #{header.description}")) * 2.0
            body = File.read(header.path)
            body_score = score_tokens(query_tokens, @tokenizer.tokenize(body))
            { header: header, score: meta_score + body_score }
          end

          scored.sort_by { |s| -s[:score] }.first(limit)
        end

        def load_memory_prompt
          index_path = File.join(@memory_dir, INDEX_FILE)
          index = File.exist?(index_path) ? File.read(index_path) : ""
          memories = scan_memory_files.first(10).map { |h| "- #{h.name}: #{h.description}" }
          "## Memory\n\n#{index}\n\n### Available Memories\n#{memories.join("\n")}"
        end

        private

        def get_project_memory_dir(project_dir)
          File.join(project_dir, ".openharness", "memory")
        end

        def parse_memory_file(path)
          content = File.read(path)
          if content.start_with?("---")
            frontmatter = content.split("---", 3)[1]
            meta = YAML.safe_load(frontmatter)
            MemoryHeader.new(
              name: meta["name"] || File.basename(path, ".md"),
              description: meta["description"],
              type: meta["type"],
              path: path,
              modified_at: File.mtime(path)
            )
          else
            MemoryHeader.new(
              name: File.basename(path, ".md"),
              description: nil, type: nil,
              path: path, modified_at: File.mtime(path)
            )
          end
        end

        def score_tokens(query_tokens, target_tokens)
          return 0.0 if query_tokens.empty? || target_tokens.empty?
          target_set = target_tokens.to_set
          matches = query_tokens.count { |t| target_set.include?(t) }
          matches.to_f / query_tokens.length
        end
      end
    end
  end
end
