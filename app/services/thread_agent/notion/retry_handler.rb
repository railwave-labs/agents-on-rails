# frozen_string_literal: true

module ThreadAgent
  module Notion
    class RetryHandler < ThreadAgent::RetryHandler
      # Notion-specific retryable errors from the notion-ruby-client gem
      NOTION_RETRYABLE_ERRORS = [
        ::Notion::Api::Errors::TimeoutError,
        ::Notion::Api::Errors::UnavailableError,
        ::Notion::Api::Errors::InternalError,
        ::Notion::Api::Errors::HttpRequestError,
        ::Notion::Api::Errors::ServerError
      ].freeze

      # Non-retryable Notion errors (permanent failures)
      NOTION_NON_RETRYABLE_ERRORS = [
        ::Notion::Api::Errors::Unauthorized,    # Authentication issues
        ::Notion::Api::Errors::Forbidden,       # Permission issues
        ::Notion::Api::Errors::BadRequest,      # Invalid request format
        ::Notion::Api::Errors::ObjectNotFound   # Resource not found
      ].freeze

      def initialize(max_attempts: DEFAULT_MAX_ATTEMPTS, **options)
        super(
          max_attempts: max_attempts,
          retryable_errors: NOTION_RETRYABLE_ERRORS + GENERIC_RETRYABLE_ERRORS,
          non_retryable_errors: NOTION_NON_RETRYABLE_ERRORS,
          final_error_class: ThreadAgent::NotionError,
          **options
        )
      end
    end
  end
end
