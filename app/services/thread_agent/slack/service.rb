# frozen_string_literal: true

module ThreadAgent
  module Slack
    class Service
      attr_reader :bot_token, :signing_secret, :timeout, :open_timeout, :max_retries, :webhook_validator

      DEFAULT_MAX_RETRIES = 3
      DEFAULT_INITIAL_DELAY = 1.0
      DEFAULT_MAX_DELAY = 30.0

      def initialize(bot_token: nil, signing_secret: nil, timeout: 15, open_timeout: 5, max_retries: 3)
        @bot_token = bot_token || ThreadAgent.configuration.slack_bot_token
        @signing_secret = signing_secret || ThreadAgent.configuration.slack_signing_secret
        @timeout = timeout
        @open_timeout = open_timeout
        @max_retries = max_retries

        validate_configuration!

        @webhook_validator = WebhookValidator.new(@signing_secret)
      end

      def client
        @client ||= initialize_client
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

      # Validate a Slack webhook payload
      # @param payload [Hash, String] The webhook payload
      # @param headers [Hash] The request headers containing signature
      # @return [ThreadAgent::Result] Result object with validated payload or error
      def validate_webhook(payload, headers)
        webhook_validator.validate(payload, headers)
      end

      # Fetch a thread from a Slack channel
      # @param channel_id [String] The Slack channel ID
      # @param thread_ts [String] The timestamp of the parent message
      # @return [ThreadAgent::Result] Result object with thread data or error
      def fetch_thread(channel_id, thread_ts)
        validate_thread_params!(channel_id, thread_ts)

        begin
          # Get the parent message first
          parent_message = with_retries do
            client.conversations_history(
              channel: channel_id,
              latest: thread_ts,
              limit: 1,
              inclusive: true
            ).messages.first
          end

          return ThreadAgent::Result.failure("Parent message not found") unless parent_message

          # Get replies in the thread
          replies = with_retries do
            client.conversations_replies(
              channel: channel_id,
              ts: thread_ts
            ).messages
          end

          formatted_data = MessageFormatter.format_thread_data(parent_message, replies)
          ThreadAgent::Result.success(formatted_data)
        rescue ThreadAgent::SlackError => e
          ThreadAgent::Result.failure(e.message)
        rescue StandardError => e
          ThreadAgent::Result.failure("Unexpected error: #{e.message}")
        end
      end

      # Create a modal for workspace, database, and template selection
      # @param trigger_id [String] The Slack trigger ID for the modal
      # @param workspaces [Array<Hash>] List of available workspaces
      # @param templates [Array<Hash>] List of available templates
      # @return [ThreadAgent::Result] Result object with modal payload or error
      def create_modal(trigger_id, workspaces, templates = [])
        return ThreadAgent::Result.failure("Missing trigger_id") if trigger_id.blank?
        return ThreadAgent::Result.failure("No workspaces available") if workspaces.blank?

        begin
          modal_payload = ModalBuilder.build_thread_capture_modal(workspaces, templates)

          response = with_retries do
            client.views_open(
              trigger_id: trigger_id,
              view: modal_payload
            )
          end

          ThreadAgent::Result.success(response)
        rescue ThreadAgent::SlackError => e
          ThreadAgent::Result.failure(e.message)
        rescue StandardError => e
          ThreadAgent::Result.failure("Unexpected error: #{e.message}")
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

      def initialize_client
        ::Slack::Web::Client.new(token: bot_token).tap do |client|
          # Configure timeout settings
          client.timeout = timeout
          client.open_timeout = open_timeout

          # Configure logging and retry settings
          client.logger = Rails.logger
          client.default_max_retries = max_retries
        end
      rescue StandardError => e
        raise ThreadAgent::SlackError, "Failed to initialize Slack client: #{e.message}"
      end

      def validate_configuration!
        unless bot_token.present?
          raise ThreadAgent::SlackError, "Missing Slack bot token"
        end

        unless signing_secret.present?
          raise ThreadAgent::SlackError, "Missing Slack signing secret"
        end
      end

      def validate_thread_params!(channel_id, thread_ts)
        raise ThreadAgent::SlackError, "Missing channel_id" if channel_id.blank?
        raise ThreadAgent::SlackError, "Missing thread_ts" if thread_ts.blank?
      end
    end
  end
end
