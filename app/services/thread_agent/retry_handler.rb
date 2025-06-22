# frozen_string_literal: true

module ThreadAgent
  class RetryHandler
    DEFAULT_MAX_ATTEMPTS = 3
    DEFAULT_BASE_INTERVAL = 1.0
    DEFAULT_BACKOFF_FACTOR = 2.0
    DEFAULT_MAX_INTERVAL = 30.0
    DEFAULT_JITTER = true

    # Generic network and connection errors that any service might encounter
    GENERIC_RETRYABLE_ERRORS = [
      Net::ReadTimeout,            # Network read timeouts
      Net::OpenTimeout,            # Network connection timeouts
      Timeout::Error,              # General timeout errors
      Errno::ECONNRESET,           # Connection reset by peer
      Errno::ECONNREFUSED,         # Connection refused
      SocketError                  # DNS and socket-level errors
    ].freeze

    DEFAULT_RETRYABLE_ERRORS = ([ ThreadAgent::Error ] + GENERIC_RETRYABLE_ERRORS).freeze

    attr_reader :max_attempts, :base_interval, :backoff_factor, :max_interval, :jitter, :retryable_errors, :non_retryable_errors

    # Initialize a new retry handler with configurable parameters
    # @param max_attempts [Integer] Maximum number of retry attempts
    # @param base_interval [Float] Initial delay between retries in seconds
    # @param backoff_factor [Float] Multiplier for exponential backoff
    # @param max_interval [Float] Maximum delay between retries in seconds
    # @param jitter [Boolean] Whether to add randomization to delay intervals
    # @param retryable_errors [Array<Class>] Error classes that should trigger retries
    # @param non_retryable_errors [Array<Class>] Error classes that should never retry (takes precedence over retryable_errors)
    # @param final_error_class [Class] Error class to raise when retries are exhausted
    def initialize(
      max_attempts: DEFAULT_MAX_ATTEMPTS,
      base_interval: DEFAULT_BASE_INTERVAL,
      backoff_factor: DEFAULT_BACKOFF_FACTOR,
      max_interval: DEFAULT_MAX_INTERVAL,
      jitter: DEFAULT_JITTER,
      retryable_errors: DEFAULT_RETRYABLE_ERRORS,
      non_retryable_errors: [],
      final_error_class: ThreadAgent::Error
    )
      @max_attempts = max_attempts
      @base_interval = base_interval
      @backoff_factor = backoff_factor
      @max_interval = max_interval
      @jitter = jitter
      @retryable_errors = retryable_errors
      @non_retryable_errors = non_retryable_errors
      @final_error_class = final_error_class
    end

    # Execute a block with retry logic and exponential backoff
    # @param max_attempts [Integer] Override the default max attempts for this call
    # @param base_interval [Float] Override the default base interval for this call
    # @param max_interval [Float] Override the default max interval for this call
    # @param jitter [Boolean] Override the default jitter setting for this call
    # @param retryable_errors [Array<Class>] Override the default retryable errors for this call
    # @param context [String] Optional context for logging
    # @return [Object] The result of the block
    # @raise [ThreadAgent::Error] When retries are exhausted
    def retry_with(
      max_attempts: nil,
      base_interval: nil,
      max_interval: nil,
      jitter: nil,
      retryable_errors: nil,
      context: nil
    )
      attempt_count = 0
      attempts = max_attempts || self.max_attempts
      interval = base_interval || self.base_interval
      max_interval_override = max_interval || self.max_interval
      use_jitter = jitter.nil? ? self.jitter : jitter
      errors_to_retry = retryable_errors || self.retryable_errors

      begin
        before_retry(attempt_count) if respond_to?(:before_retry, true)
        result = yield
        after_retry(attempt_count) if respond_to?(:after_retry, true)
        result
      rescue StandardError => e
        if should_retry?(e, errors_to_retry, attempt_count, attempts)
          attempt_count += 1
          sleep_interval = calculate_interval(attempt_count, interval, max_interval_override, use_jitter)

          log_retry_attempt(e, attempt_count, attempts, sleep_interval, context)
          sleep sleep_interval

          retry
        else
          handle_final_error(e, attempt_count, context)
        end
      end
    end

    private

    # Determine if an error should trigger a retry
    # @param error [StandardError] The error that occurred
    # @param retryable_errors [Array<Class>] Error classes that should trigger retries
    # @param attempt_count [Integer] Current attempt number (0-based)
    # @param max_attempts [Integer] Maximum number of attempts
    # @return [Boolean] Whether to retry
    def should_retry?(error, retryable_errors, attempt_count, max_attempts)
      return false if attempt_count >= max_attempts

      # Check non-retryable errors first (takes precedence)
      return false if @non_retryable_errors.any? { |error_class| error.is_a?(error_class) }

      # Then check if it's in the retryable errors list
      return false unless retryable_errors.any? { |error_class| error.is_a?(error_class) }

      true
    end

    # Calculate the sleep interval for the next retry
    # @param attempt_count [Integer] Current attempt number (1-based for calculations)
    # @param base_interval [Float] Base interval in seconds
    # @param max_interval [Float] Maximum interval in seconds
    # @param use_jitter [Boolean] Whether to add jitter
    # @return [Float] Sleep interval in seconds
    def calculate_interval(attempt_count, base_interval, max_interval, use_jitter)
      # Calculate exponential backoff: base_interval * (backoff_factor ** (attempt_count - 1))
      exponential_interval = base_interval * (backoff_factor ** (attempt_count - 1))

      # Cap at max_interval
      capped_interval = [ exponential_interval, max_interval ].min

      # Apply jitter if enabled (±25% randomization)
      if use_jitter
        jitter_range = capped_interval * 0.25
        jittered_interval = capped_interval + (rand * 2 - 1) * jitter_range
        # Ensure jittered interval is never negative
        [ jittered_interval, 0.1 ].max
      else
        capped_interval
      end
    end

    # Log a retry attempt
    # @param error [StandardError] The error that caused the retry
    # @param attempt_count [Integer] Current attempt number
    # @param max_attempts [Integer] Maximum number of attempts
    # @param sleep_interval [Float] Sleep interval before retry
    # @param context [String] Optional context for logging
    def log_retry_attempt(error, attempt_count, max_attempts, sleep_interval, context)
      context_tag = context ? "[#{context}] " : ""
      Rails.logger.warn(
        "#{context_tag}Retry attempt #{attempt_count}/#{max_attempts} " \
        "for #{error.class}: #{error.message}. " \
        "Sleeping #{sleep_interval.round(2)}s before retry."
      )
    end

    # Handle the final error when retries are exhausted
    # @param error [StandardError] The original error
    # @param attempt_count [Integer] Total number of attempts made
    # @param context [String] Optional context for logging
    # @raise [ThreadAgent::Error] The wrapped final error
    def handle_final_error(error, attempt_count, context)
      context_tag = context ? "[#{context}] " : ""
      final_message = "#{context_tag}Operation failed after #{attempt_count} retries: #{error.message}"

      Rails.logger.error(final_message)
      raise @final_error_class, final_message
    end
  end
end
