# frozen_string_literal: true

class NetworkError < ApplicationError
  def initialize(message = nil, code: nil, context: {}, retryable: true)
    super(message, code: code || 'connection.failed', context: context, retryable: retryable)
  end
end
