# frozen_string_literal: true

class ValidationError < ApplicationError
  def initialize(message = nil, code: nil, context: {}, retryable: false)
    super(message, code: code || 'validation.failed', context: context, retryable: retryable)
  end
end
