# frozen_string_literal: true

module ErrorHandler
  def self.standardize_error(error, context: {}, service: nil)
    enriched_context = context.merge(
      original_error_class: error.class.name,
      original_message: error.message,
      service: service
    ).compact

    case error
    when JSON::ParserError
      ::ServiceParseError.new(
        "Failed to parse JSON response: #{error.message}",
        code: 'parse.json.failed',
        context: enriched_context
      )

    when Net::ReadTimeout, Net::OpenTimeout, Timeout::Error
      RequestTimeoutError.new(
        "Request timed out: #{error.message}",
        code: 'request.timeout',
        context: enriched_context
      )

    when Errno::ECONNRESET, Errno::ECONNREFUSED, SocketError
      NetworkError.new(
        "Connection failed: #{error.message}",
        code: 'connection.failed',
        context: enriched_context
      )

    when Faraday::Error
      NetworkError.new(
        "HTTP request failed: #{error.message}",
        code: 'http.request.failed',
        context: enriched_context
      )

    when defined?(OpenAI::Error) && OpenAI::Error
      if error.message.include?('401') || error.message.include?('Unauthorized')
        Openai::AuthError.new(
          "OpenAI authentication failed: #{error.message}",
          context: enriched_context
        )
      elsif error.message.include?('429') || error.message.include?('rate limit')
        Openai::RateLimitError.new(
          "OpenAI rate limit exceeded: #{error.message}",
          context: enriched_context
        )
      else
        Openai::Error.new(
          "OpenAI API error: #{error.message}",
          context: enriched_context
        )
      end

    when ActiveRecord::RecordNotFound
      ValidationError.new(
        "Record not found: #{error.message}",
        code: 'validation.record_not_found',
        context: enriched_context
      )

    when ActiveRecord::RecordInvalid
      ValidationError.new(
        "Record validation failed: #{error.message}",
        code: 'validation.record_invalid',
        context: enriched_context
      )

    when ApplicationError
      error

    else
      ApplicationError.new(
        "Unexpected error: #{error.message}",
        code: 'error.unexpected',
        context: enriched_context
      )
    end
  end

  def self.to_result(error, context: {}, service: nil)
    standardized_error = case error
    when ApplicationError
                          error
    else
                          standardize_error(error, context: context, service: service)
    end

    Result.failure(standardized_error.message, standardized_error.to_h)
  end

  def self.create_error(error_class, message, code: nil, context: {})
    if error_class <= ApplicationError
      error_class.new(message, code: code, context: context)
    else
      ApplicationError.new(message, code: code || 'error.unknown', context: context)
    end
  end

  def self.log_error(error, logger: Rails.logger, level: :error)
    log_data = {
      error_class: error.class.name,
      error_code: error.respond_to?(:code) ? error.code : nil,
      error_message: error.message,
      retryable: error.respond_to?(:retryable?) ? error.retryable? : nil,
      context: error.respond_to?(:context) ? error.context : {},
      timestamp: Time.current.iso8601
    }

    logger.send(level, log_data.to_json)
  end

  def self.handle_error(error, context: {}, service: nil, logger: Rails.logger)
    standardized_error = standardize_error(error, context: context, service: service)
    log_error(standardized_error, logger: logger)
    to_result(standardized_error)
  end
end
