# frozen_string_literal: true

require "faraday"
require_relative "../base_tool"

module Openharness
  module Rb
    module Tools
      module Builtin
        class WebFetchTool < BaseTool
          def name
            "web_fetch"
          end

          def description
            "Fetch the content of a web page at a given URL"
          end

          def input_schema
            {
              type: "object",
              properties: {
                url: { type: "string", description: "URL to fetch" }
              },
              required: ["url"]
            }
          end

          private

          def execute(input, _context)
            url = input[:url] || input["url"]
            response = Faraday.get(url)

            if response.status >= 200 && response.status < 300
              Models::ToolResult.new(text: response.body)
            else
              Models::ToolResult.new(
                text: "HTTP #{response.status}: Failed to fetch #{url}",
                is_error: true
              )
            end
          rescue Faraday::ConnectionFailed => e
            Models::ToolResult.new(text: "Connection failed: #{e.message}", is_error: true)
          rescue Faraday::TimeoutError => e
            Models::ToolResult.new(text: "Request timed out: #{e.message}", is_error: true)
          end
        end
      end
    end
  end
end
