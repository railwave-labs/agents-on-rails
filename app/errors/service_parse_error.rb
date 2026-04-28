# frozen_string_literal: true

class ServiceParseError < ApplicationError
  def initialize(message = nil, code: nil, context: {}, retryable: false)
    super(message, code: code || 'parse.json.failed', context: context, retryable: retryable)
  end
end
