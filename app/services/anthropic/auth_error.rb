# frozen_string_literal: true

require_dependency "anthropic/error"

module Anthropic
  class AuthError < Anthropic::Error
    def initialize(message = nil, code: nil, context: {}, retryable: false)
      super(message || "Anthropic authentication failed", code: code || 'anthropic.auth.invalid', context: context, retryable: retryable)
    end
  end
end
