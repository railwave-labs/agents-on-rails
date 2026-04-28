# frozen_string_literal: true

class RequestTimeoutError < ApplicationError
  def initialize(message = nil, code: nil, context: {}, retryable: true)
    super(message, code: code || 'request.timeout', context: context, retryable: retryable)
  end
end
