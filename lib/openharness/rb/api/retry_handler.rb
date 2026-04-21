# frozen_string_literal: true

module Openharness
  module Rb
    module Api
      module RetryHandler
        NON_RETRYABLE_ERRORS = [
          "RubyLLM::UnauthorizedError",
          "RubyLLM::BadRequestError",
        ].freeze

        def with_retry(max_retries: 3, base_delay: 1.0)
          attempts = 0
          begin
            yield
          rescue StandardError => e
            attempts += 1
            raise if attempts > max_retries
            raise if non_retryable?(e)

            delay = base_delay * (2**attempts) + rand(0.0..1.0)
            sleep(delay)
            retry
          end
        end

        private

        def non_retryable?(error)
          NON_RETRYABLE_ERRORS.any? { |name| error.class.name == name } ||
            error.is_a?(Openharness::Rb::AuthenticationFailure)
        end
      end
    end
  end
end
