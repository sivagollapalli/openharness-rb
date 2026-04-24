# frozen_string_literal: true

require "yaml"
require "fileutils"
require "securerandom"

module Openharness
  module Rb
    module Memory
      class MemorySystem
        INDEX_FILE = "MEMORY.md"

        def initialize(project_dir: Dir.pwd)
          @memory_dir = get_project_memory_dir(project_dir)
          @tokenizer = Tokenizer.new
        end

        # Save a new memory to disk and rebuild the index.
        #
        # @param name [String] short identifier (used as filename slug)
        # @param description [String] one-line summary
        # @param content [String] full body (markdown)
        # @param type [String, nil] category — "lesson", "mistake", "decision", etc.
        # @return [MemoryHeader] the saved memory's header
        def save_memory(name:, description:, content:, type: nil)
          FileUtils.mkdir_p(@memory_dir)

          slug = name.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-|-$/, "")
          slug = "#{slug}-#{SecureRandom.hex(3)}" if File.exist?(File.join(@memory_dir, "#{slug}.md"))
          path = File.join(@memory_dir, "#{slug}.md")

          frontmatter = { "name" => name, "description" => description }
          frontmatter["type"] = type if type

          File.write(path, "---\n#{YAML.dump(frontmatter)}---\n\n#{content}\n")

          rebuild_index

          MemoryHeader.new(
            name: name,
            description: description,
            type: type,
            path: path,
            modified_at: File.mtime(path)
          )
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

        # Build the memory prompt for the system prompt.
        # When a query is provided, relevant memories are loaded in full.
        # Otherwise falls back to the index + catalog.
        def load_memory_prompt(query: nil)
          index_content = load_index_content
          sections = ["## Memory\n"]
          sections << index_content unless index_content.empty?

          if query
            relevant = find_relevant_memories(query, limit: 5)
            if relevant.any? { |r| r[:score] > 0.0 }
              sections << "### Relevant Memories\n"
              relevant.each do |r|
                next if r[:score] <= 0.0

                body = File.read(r[:header].path)
                # Strip frontmatter for the prompt
                body = body.split("---", 3).last.strip if body.start_with?("---")
                sections << "#### #{r[:header].name}\n#{body}\n"
              end
            end
          end

          # Always include the catalog so the agent knows what else exists
          catalog = scan_memory_files.first(15).map { |h| "- #{h.name}: #{h.description || '(no description)'}" }
          unless catalog.empty?
            sections << "### Available Memories\n#{catalog.join("\n")}"
          end

          sections.join("\n")
        end

        # Rebuild the MEMORY.md index from all memory files on disk.
        def rebuild_index
          headers = scan_memory_files
          lines = ["# Memory Index\n"]
          lines << "Auto-generated index of #{headers.length} memories.\n"

          grouped = headers.group_by { |h| h.type || "general" }
          grouped.sort_by { |type, _| type }.each do |type, entries|
            lines << "## #{type.capitalize}\n"
            entries.each do |h|
              lines << "- **#{h.name}**: #{h.description || '(no description)'}"
            end
            lines << ""
          end

          index_path = File.join(@memory_dir, INDEX_FILE)
          File.write(index_path, lines.join("\n") + "\n")
        end

        private

        def get_project_memory_dir(project_dir)
          File.join(project_dir, ".openharness", "memory")
        end

        def load_index_content
          index_path = File.join(@memory_dir, INDEX_FILE)
          File.exist?(index_path) ? File.read(index_path).strip : ""
        end

        def parse_memory_file(path)
          content = File.read(path)
          if content.start_with?("---")
            frontmatter = content.split("---", 3)[1]
            meta = YAML.safe_load(frontmatter) || {}
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
