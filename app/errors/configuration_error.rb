# frozen_string_literal: true

class ConfigurationError < ApplicationError
  def initialize(message = nil, code: nil, context: {}, retryable: false)
    super(message, code: code || 'configuration.invalid', context: context, retryable: retryable)
  end
end
