# frozen_string_literal: true

module ThreadAgent
  # Provides consistent error handling patterns across all ThreadAgent services
  module ErrorHandler
    # Convert various exception types to ThreadAgent errors with appropriate context
    #
    # @param error [Exception] The original exception
    # @param context [Hash] Additional context to include with the error
    # @param service [String] The service name for error categorization
    # @return [ThreadAgent::Error] A standardized ThreadAgent error
    def self.standardize_error(error, context: {}, service: nil)
      enriched_context = context.merge(
        original_error_class: error.class.name,
        original_message: error.message,
        service: service
      ).compact

      case error
      # JSON parsing errors
      when JSON::ParserError
        ThreadAgent::ParseError.new(
          "Failed to parse JSON response: #{error.message}",
          code: "parse.json.failed",
          context: enriched_context
        )

      # Network and connection errors
      when Net::ReadTimeout, Net::OpenTimeout, Timeout::Error
        ThreadAgent::TimeoutError.new(
          "Request timed out: #{error.message}",
          code: "request.timeout",
          context: enriched_context
        )

      when Errno::ECONNRESET, Errno::ECONNREFUSED, SocketError
        ThreadAgent::ConnectionError.new(
          "Connection failed: #{error.message}",
          code: "connection.failed",
          context: enriched_context
        )

      when Faraday::Error
        ThreadAgent::ConnectionError.new(
          "HTTP request failed: #{error.message}",
          code: "http.request.failed",
          context: enriched_context
        )

      # OpenAI specific errors
      when defined?(OpenAI::Error) && OpenAI::Error
        if error.message.include?("401") || error.message.include?("Unauthorized")
          ThreadAgent::OpenaiAuthError.new(
            "OpenAI authentication failed: #{error.message}",
            context: enriched_context
          )
        elsif error.message.include?("429") || error.message.include?("rate limit")
          ThreadAgent::OpenaiRateLimitError.new(
            "OpenAI rate limit exceeded: #{error.message}",
            context: enriched_context
          )
        else
          ThreadAgent::OpenaiError.new(
            "OpenAI API error: #{error.message}",
            context: enriched_context
          )
        end

      # Database errors
      when ActiveRecord::RecordNotFound
        ThreadAgent::ValidationError.new(
          "Record not found: #{error.message}",
          code: "validation.record_not_found",
          context: enriched_context
        )

      when ActiveRecord::RecordInvalid
        ThreadAgent::ValidationError.new(
          "Record validation failed: #{error.message}",
          code: "validation.record_invalid",
          context: enriched_context
        )

      # ThreadAgent errors (already standardized)
      when ThreadAgent::Error
        error

      # All other errors
      else
        ThreadAgent::Error.new(
          "Unexpected error: #{error.message}",
          code: "error.unexpected",
          context: enriched_context
        )
      end
    end

    # Convert an error to a ThreadAgent::Result
    #
    # @param error [Exception, ThreadAgent::Error] The error to convert
    # @param context [Hash] Additional context to include
    # @param service [String] The service name for error categorization
    # @return [ThreadAgent::Result] A failure result with standardized error
    def self.to_result(error, context: {}, service: nil)
      standardized_error = case error
      when ThreadAgent::Error
                            error
      else
                            standardize_error(error, context: context, service: service)
      end

      ThreadAgent::Result.failure(standardized_error.message, standardized_error.to_h)
    end

    # Create a standardized error with contextual information
    #
    # @param error_class [Class] The ThreadAgent error class to instantiate
    # @param message [String] The error message
    # @param code [String] The error code (optional, will use class default if not provided)
    # @param context [Hash] Additional context information
    # @return [ThreadAgent::Error] The created error instance
    def self.create_error(error_class, message, code: nil, context: {})
      if error_class < ThreadAgent::Error
        error_class.new(message, code: code, context: context)
      else
        ThreadAgent::Error.new(message, code: code || "error.unknown", context: context)
      end
    end

    # Log an error with structured format including context
    #
    # @param error [ThreadAgent::Error] The error to log
    # @param logger [Logger] The logger instance (defaults to Rails.logger)
    # @param level [Symbol] The log level (:error, :warn, :info)
    def self.log_error(error, logger: Rails.logger, level: :error)
      log_data = {
        error_class: error.class.name,
        error_code: error.code,
        error_message: error.message,
        retryable: error.retryable?,
        context: error.context,
        timestamp: Time.current.iso8601
      }

      logger.send(level, log_data.to_json)
    end

    # Handle an error by standardizing, logging, and converting to Result
    #
    # @param error [Exception] The original error
    # @param context [Hash] Additional context
    # @param service [String] The service name
    # @param logger [Logger] The logger instance
    # @return [ThreadAgent::Result] A failure result
    def self.handle_error(error, context: {}, service: nil, logger: Rails.logger)
      standardized_error = standardize_error(error, context: context, service: service)
      log_error(standardized_error, logger: logger)
      to_result(standardized_error)
    end
  end
end
