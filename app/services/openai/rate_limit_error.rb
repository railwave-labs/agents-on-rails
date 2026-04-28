# frozen_string_literal: true

module Openai
  class RateLimitError < Openai::Error
    def initialize(message = nil, code: nil, context: {}, retryable: true)
      super(message, code: code || 'openai.rate_limit.exceeded', context: context, retryable: retryable)
    end
  end
end
