# frozen_string_literal: true

module Openharness
  module Rb
    # Base class for all API-related errors
    class OpenHarnessApiError < StandardError; end

    # Raised when API authentication fails (e.g., invalid or expired API key)
    class AuthenticationFailure < OpenHarnessApiError; end

    # Raised when the API rate limit is exceeded
    class RateLimitFailure < OpenHarnessApiError
      attr_reader :retry_after

      def initialize(message = nil, retry_after: nil)
        @retry_after = retry_after
        super(message)
      end
    end

    # Raised when an API request fails with a non-success status code
    class RequestFailure < OpenHarnessApiError
      attr_reader :status_code, :response_body

      def initialize(message = nil, status_code: nil, response_body: nil)
        @status_code = status_code
        @response_body = response_body
        super(message)
      end
    end

    # Raised when the query engine exceeds the maximum number of turns
    class MaxTurnsExceeded < Error; end

    # Raised when registering a tool with a name that already exists
    class DuplicateToolError < Error; end

    # Raised when looking up a tool that is not registered
    class ToolNotFoundError < Error; end

    # Raised when registering an agent with a name that already exists
    class DuplicateAgentError < Error; end

    # Raised when looking up an agent that is not registered
    class AgentNotFoundError < Error; end

    # Raised when looking up a background task that does not exist
    class TaskNotFoundError < Error; end

    # Raised when looking up a skill that is not registered
    class SkillNotFoundError < Error; end

    # Raised when an MCP server is not connected
    class McpServerNotConnectedError < Error; end

    # Raised when looking up a session that does not exist
    class SessionNotFoundError < Error; end

    # Raised for invalid or unsupported configuration
    class ConfigurationError < Error; end

    # Raised when a provider cannot be detected from the given API key
    class UnknownProviderError < Error; end

    # Raised when registering a background task with a name that already exists
    class DuplicateTaskError < Error; end
  end
end
