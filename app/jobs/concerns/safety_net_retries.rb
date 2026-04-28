# frozen_string_literal: true

require_dependency "anthropic/api_rate_limit_error"

# Safety net retry configuration for jobs that handle external service calls.
# These retries kick in when service-level retries are exhausted and provide
# a last line of defense against transient failures.
module SafetyNetRetries
  extend ActiveSupport::Concern

  included do
    # Slack service errors (after service-level retries fail)
    retry_on Slack::Error, wait: 30.seconds, attempts: 3

    # OpenAI service errors (after service-level retries fail)
    retry_on Openai::Error, wait: 30.seconds, attempts: 3

    # Anthropic service errors (after service-level retries fail)
    # Anthropic::ApiRateLimitError and Anthropic::AuthError are subclasses of Anthropic::Error
    retry_on Anthropic::ApiRateLimitError, wait: 30.seconds, attempts: 3

    # Generic network/connection errors that might bypass service-level handling
    retry_on Net::ReadTimeout, Net::OpenTimeout, Timeout::Error, wait: 30.seconds, attempts: 3
    retry_on Errno::ECONNRESET, Errno::ECONNREFUSED, SocketError, wait: 30.seconds, attempts: 3

    # Faraday errors (HTTP client used by both services)
    retry_on Faraday::Error, wait: 30.seconds, attempts: 3

    # Database connection issues
    retry_on ActiveRecord::ConnectionTimeoutError, wait: 30.seconds, attempts: 3
  end
end
