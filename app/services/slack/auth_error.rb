# frozen_string_literal: true

module Slack
  class AuthError < Slack::Error
    def initialize(message = nil, code: nil, context: {}, retryable: false)
      super(message, code: code || 'slack.auth.invalid', context: context, retryable: retryable)
    end
  end
end
