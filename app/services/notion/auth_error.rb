# frozen_string_literal: true

module Notion
  class AuthError < Notion::Error
    def initialize(message = nil, code: nil, context: {}, retryable: false)
      super(message, code: code || 'notion.auth.invalid', context: context, retryable: retryable)
    end
  end
end
