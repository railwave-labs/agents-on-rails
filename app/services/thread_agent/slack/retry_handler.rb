# frozen_string_literal: true

module ThreadAgent
  module Slack
    class RetryHandler
      DEFAULT_MAX_RETRIES = 3
      DEFAULT_INITIAL_DELAY = 1.0
      DEFAULT_MAX_DELAY = 30.0

      attr_reader :max_retries

      def initialize(max_retries: DEFAULT_MAX_RETRIES)
        @max_retries = max_retries
      end

      # Execute a block with retry logic and exponential backoff
      # @param max_retries [Integer] Override the default max retries for this call
      # @param initial_delay [Float] Override the default initial delay for this call
      # @param max_delay [Float] Override the default max delay for this call
      # @return [Object] The result of the block or raises an error
      def with_retries(max_retries: nil, initial_delay: nil, max_delay: nil)
        retries = 0
        max_attempts = max_retries || self.max_retries
        delay = initial_delay || DEFAULT_INITIAL_DELAY
        delay_cap = max_delay || DEFAULT_MAX_DELAY

        begin
          yield
        rescue ::Slack::Web::Api::Errors::RateLimited => e
          handle_rate_limited_error(e, retries, max_attempts, delay)
          retries += 1
          retry
        rescue ::Slack::Web::Api::Errors::TimeoutError => e
          handle_timeout_error(e, retries, max_attempts, delay, delay_cap)
          retries += 1
          delay = calculate_next_delay(delay, delay_cap)
          retry
        rescue ::Slack::Web::Api::Errors::SlackError => e
          handle_slack_error(e, retries, max_attempts, delay, delay_cap)
          retries += 1
          delay = calculate_next_delay(delay, delay_cap)
          retry
        rescue Net::ReadTimeout, Net::OpenTimeout => e
          handle_network_timeout_error(e, retries, max_attempts, delay, delay_cap)
          retries += 1
          delay = calculate_next_delay(delay, delay_cap)
          retry
        end
      end

      private

      def handle_rate_limited_error(error, retries, max_attempts, delay)
        retry_after = error.response_metadata&.dig("retry_after") || delay

        if retries < max_attempts
          sleep retry_after
        else
          raise ThreadAgent::SlackError, "Rate limit exceeded after #{retries} retries: #{error.message}"
        end
      end

      def handle_timeout_error(error, retries, max_attempts, delay, delay_cap)
        if retries < max_attempts
          sleep delay
        else
          raise ThreadAgent::SlackError, "Timeout error after #{retries} retries: #{error.message}"
        end
      end

      def handle_slack_error(error, retries, max_attempts, delay, delay_cap)
        status_code = error.response_metadata&.dig("status_code")&.to_i

        if server_error?(status_code) && retries < max_attempts
          sleep delay
        else
          error_message = if client_error?(status_code)
                            "Slack API client error (#{status_code}): #{error.message}"
          else
                            "Slack API error after #{retries} retries: #{error.message}"
          end
          raise ThreadAgent::SlackError, error_message
        end
      end

      def handle_network_timeout_error(error, retries, max_attempts, delay, delay_cap)
        if retries < max_attempts
          sleep delay
        else
          raise ThreadAgent::SlackError, "Network timeout after #{retries} retries: #{error.message}"
        end
      end

      def server_error?(status_code)
        status_code && status_code >= 500 && status_code < 600
      end

      def client_error?(status_code)
        status_code && status_code >= 400 && status_code < 500
      end

      def calculate_next_delay(current_delay, max_delay)
        [ current_delay * 2, max_delay ].min
      end
    end
  end
end
