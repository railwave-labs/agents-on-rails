# frozen_string_literal: true

module Openai
  class AuthError < Openai::Error
    def initialize(message = nil, code: nil, context: {}, retryable: false)
      super(message, code: code || 'openai.auth.invalid', context: context, retryable: retryable)
    end
  end
end
