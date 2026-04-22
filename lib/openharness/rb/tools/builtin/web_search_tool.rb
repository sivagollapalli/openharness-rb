# frozen_string_literal: true

require "ruby_llm"
require "serpapi"

module Openharness
  module Rb
    module Tools
      module Builtin
        class WebSearchTool < RubyLLM::Tool
          description "Search the web for information (placeholder — configure a search provider)"

          param :query, desc: "Search query"

          def execute(query:)
            if ENV['SERPAPI_KEY']
              client = SerpApi::Client.new(
                engine: 'google',
                api_key: ENV['SERPAPI_KEY'],
                async: false, # non-blocking HTTP request see: Search Asynchronous (default: false)
                persistent: true, # leave socket connection open for faster response time see: Search at scale (default: true)
                timeout: 5, # HTTP timeout in seconds on the client side only. (default: 120s)
                symbolize_names: true # turn on/off JSON keys to symbols (default: on, more efficient)
              )
              
              params = {
                engine: "google",
                q: query,
              }

              results = client.search(params)
            else
              { error: "Web search is not yet configured. Query: #{query}" }
            end
          end
        end
      end
    end
  end
end
