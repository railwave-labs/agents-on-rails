# frozen_string_literal: true

module ThreadAgent
  module Openai
    class RetryHandler < ThreadAgent::RetryHandler
      # OpenAI-specific retryable errors
      OPENAI_SPECIFIC_ERRORS = [
        OpenAI::Error,               # Base error class from ruby-openai (includes transient errors)
        Faraday::Error               # HTTP client errors (ruby-openai uses Faraday)
      ].freeze

      # Non-retryable OpenAI errors (permanent failures)
      OPENAI_NON_RETRYABLE_ERRORS = [
        OpenAI::AuthenticationError, # API key issues - need manual fix
        OpenAI::ConfigurationError   # Configuration issues - need code fix
      ].freeze

      # Combined OpenAI-specific and generic retryable errors
      OPENAI_RETRYABLE_ERRORS = (OPENAI_SPECIFIC_ERRORS + GENERIC_RETRYABLE_ERRORS).freeze

      def initialize(max_attempts: DEFAULT_MAX_ATTEMPTS, **options)
        super(
          max_attempts: max_attempts,
          retryable_errors: OPENAI_RETRYABLE_ERRORS,
          non_retryable_errors: OPENAI_NON_RETRYABLE_ERRORS,
          final_error_class: ThreadAgent::OpenaiError,
          jitter: false,  # Disable jitter by default for deterministic behavior
          **options       # Pass through any other options (like jitter override)
        )
      end
    end
  end
end
