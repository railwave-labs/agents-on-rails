# frozen_string_literal: true

module Notion
  class Error < ApplicationError
    def initialize(message = nil, code: nil, context: {}, retryable: true)
      super(message, code: code || 'notion.request.failed', context: context, retryable: retryable)
    end
  end
end
