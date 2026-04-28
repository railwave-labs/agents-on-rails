# frozen_string_literal: true

module Slack
  class RateLimitError < Slack::Error
    def initialize(message = nil, code: nil, context: {}, retryable: true)
      super(message, code: code || 'slack.rate_limit.exceeded', context: context, retryable: retryable)
    end
  end
end
