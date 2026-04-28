# frozen_string_literal: true

module Notion
  class RateLimitError < Notion::Error
    def initialize(message = nil, code: nil, context: {}, retryable: true)
      super(message, code: code || 'notion.rate_limit.exceeded', context: context, retryable: retryable)
    end
  end
end
