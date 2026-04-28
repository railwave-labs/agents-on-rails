# frozen_string_literal: true

require_dependency "anthropic/error"

module Anthropic
  # Application-level rate-limit exception for Anthropic API calls.
  # Named ApiRateLimitError to avoid conflicting with Anthropic::RateLimitError,
  # which the official SDK defines as a model class (API response body shape).
  class ApiRateLimitError < Anthropic::Error
    def initialize(message = nil, code: nil, context: {}, retryable: true)
      super(message || "Anthropic rate limit exceeded", code: code || 'anthropic.rate_limit', context: context, retryable: retryable)
    end
  end
end
