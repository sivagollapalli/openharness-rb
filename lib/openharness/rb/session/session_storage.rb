# frozen_string_literal: true

require "json"
require "fileutils"

module Openharness
  module Rb
    module Session
      class SessionStorage
        DEFAULT_DIR = File.expand_path("~/.openharness/sessions")

        def initialize(directory: DEFAULT_DIR)
          @directory = directory
          FileUtils.mkdir_p(@directory)
        end

        def save(session_id, messages:, cost_tracker:, metadata: {})
          data = {
            session_id: session_id,
            messages: messages.map(&:to_h),
            cost: cost_tracker.summary,
            metadata: metadata,
            saved_at: Time.now.iso8601
          }
          File.write(session_path(session_id), JSON.pretty_generate(data))
        end

        def load(session_id)
          path = session_path(session_id)
          raise SessionNotFoundError, session_id unless File.exist?(path)

          data = JSON.parse(File.read(path), symbolize_names: true)
          {
            messages: data[:messages].map { |m| Models::ConversationMessage.from_h(m) },
            cost: data[:cost],
            metadata: data[:metadata]
          }
        end

        private

        def session_path(id)
          File.join(@directory, "#{id}.json")
        end
      end
    end
  end
end
