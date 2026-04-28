# frozen_string_literal: true

module Openai
  class Error < ApplicationError
    def initialize(message = nil, code: nil, context: {}, retryable: true)
      super(message, code: code || 'openai.request.failed', context: context, retryable: retryable)
    end
  end
end
