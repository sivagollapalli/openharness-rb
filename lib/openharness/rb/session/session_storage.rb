# frozen_string_literal: true

require "json"
require "fileutils"
require "securerandom"

module Openharness
  module Rb
    module Session
      class SessionStorage
        attr_reader :session_id, :directory

        def initialize(project_dir: Dir.pwd, session_id: nil)
          @directory = File.join(project_dir, ".openharness", "sessions")
          @session_id = session_id || SecureRandom.uuid
          @conversation = []
          @started_at = Time.now.iso8601
          FileUtils.mkdir_p(@directory)
        end

        # Record a user message in the conversation log.
        def record_user_message(text)
          @conversation << {
            role: "user",
            content: text,
            timestamp: Time.now.iso8601
          }
        end

        # Record an assistant message in the conversation log.
        def record_assistant_message(text, tool_calls: [], tool_results: [])
          entry = {
            role: "assistant",
            content: text,
            timestamp: Time.now.iso8601
          }
          entry[:tool_calls] = tool_calls unless tool_calls.empty?
          entry[:tool_results] = tool_results unless tool_results.empty?
          @conversation << entry
        end

        # Record a tool execution in the conversation log.
        def record_tool_call(tool_name:, tool_use_id:, arguments: {})
          @conversation << {
            role: "tool_call",
            tool_name: tool_name,
            tool_use_id: tool_use_id,
            arguments: arguments,
            timestamp: Time.now.iso8601
          }
        end

        # Record a tool result in the conversation log.
        def record_tool_result(tool_use_id:, result:, is_error: false)
          @conversation << {
            role: "tool_result",
            tool_use_id: tool_use_id,
            result: result,
            is_error: is_error,
            timestamp: Time.now.iso8601
          }
        end

        # Export the full conversation to the session JSON file.
        # Returns the file path.
        def export(cost_summary: nil, metadata: {})
          data = {
            session_id: @session_id,
            started_at: @started_at,
            exported_at: Time.now.iso8601,
            metadata: metadata,
            cost: cost_summary,
            conversation: @conversation
          }

          path = session_path(@session_id)
          File.write(path, JSON.pretty_generate(data))
          path
        end

        # Load a previous session from disk and return the conversation entries.
        # Returns a hash with :session_id, :conversation, :cost, :metadata.
        def self.load(file_path)
          unless File.exist?(file_path)
            raise SessionNotFoundError, "Session file not found: #{file_path}"
          end

          data = JSON.parse(File.read(file_path), symbolize_names: true)
          {
            session_id: data[:session_id],
            conversation: data[:conversation] || [],
            cost: data[:cost],
            metadata: data[:metadata] || {},
            started_at: data[:started_at]
          }
        end

        # Get the conversation log.
        def conversation
          @conversation.dup
        end

        # Get the number of messages in the conversation.
        def message_count
          @conversation.length
        end

        private

        def session_path(id)
          File.join(@directory, "#{id}.json")
        end
      end
    end
  end
end
