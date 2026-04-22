# frozen_string_literal: true

require "ruby_llm"

module Openharness
  module Rb
    module Tools
      module Builtin
        class WebSearchTool < RubyLLM::Tool
          description "Search the web for information (placeholder — configure a search provider)"

          param :query, desc: "Search query"

          def execute(query:)
            { error: "Web search is not yet configured. Query: #{query}" }
          end
        end
      end
    end
  end
end
