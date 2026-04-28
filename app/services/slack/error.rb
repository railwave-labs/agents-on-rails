# frozen_string_literal: true

module Slack
  class Error < ApplicationError
    def initialize(message = nil, code: nil, context: {}, retryable: true)
      super(message, code: code || 'slack.request.failed', context: context, retryable: retryable)
    end
  end
end
