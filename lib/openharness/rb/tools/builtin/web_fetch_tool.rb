# frozen_string_literal: true

require "ruby_llm"
require "faraday"

module Openharness
  module Rb
    module Tools
      module Builtin
        class WebFetchTool < RubyLLM::Tool
          description "Fetch the content of a web page at a given URL"

          def name = "web_fetch"

          param :url, desc: "URL to fetch"

          def execute(url:)
            response = Faraday.get(url)

            if response.status >= 200 && response.status < 300
              response.body
            else
              { error: "HTTP #{response.status}: Failed to fetch #{url}" }
            end
          rescue Faraday::ConnectionFailed => e
            { error: "Connection failed: #{e.message}" }
          rescue Faraday::TimeoutError => e
            { error: "Request timed out: #{e.message}" }
          end
        end
      end
    end
  end
end
