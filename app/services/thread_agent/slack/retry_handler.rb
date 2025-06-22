# frozen_string_literal: true

module ThreadAgent
  module Slack
    class RetryHandler < ThreadAgent::RetryHandler
      # Slack-specific retryable errors
      SLACK_SPECIFIC_ERRORS = [
        ::Slack::Web::Api::Errors::RateLimited,
        ::Slack::Web::Api::Errors::TimeoutError,
        ::Slack::Web::Api::Errors::SlackError
      ].freeze

      # Combined Slack-specific and generic retryable errors
      SLACK_RETRYABLE_ERRORS = (SLACK_SPECIFIC_ERRORS + GENERIC_RETRYABLE_ERRORS).freeze

      def initialize(max_attempts: DEFAULT_MAX_ATTEMPTS)
        super(
          max_attempts: max_attempts,
          retryable_errors: SLACK_RETRYABLE_ERRORS,
          final_error_class: ThreadAgent::SlackError,
          jitter: false  # Disable jitter by default for deterministic behavior
        )
      end

      private

      # Override to handle Slack retry_after headers from rate limit responses
      # @param attempt_count [Integer] Current attempt number (1-based for calculations)
      # @param base_interval [Float] Base interval in seconds
      # @param max_interval [Float] Maximum interval in seconds
      # @param use_jitter [Boolean] Whether to add jitter
      # @return [Float] Sleep interval in seconds
      def calculate_interval(attempt_count, base_interval, max_interval, use_jitter)
        # Check for rate limited error with retry_after header
        current_exception = $!
        if current_exception.is_a?(::Slack::Web::Api::Errors::RateLimited)
          retry_after = current_exception.response_metadata&.dig("retry_after")
          return retry_after.to_f if retry_after.present?
        end

        # Fall back to exponential backoff from base class
        super(attempt_count, base_interval, max_interval, use_jitter)
      end
    end
  end
end
