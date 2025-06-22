# frozen_string_literal: true

module ThreadAgent
  module Slack
    class Service
      attr_reader :slack_client, :retry_handler, :thread_fetcher, :shortcut_handler

      def initialize(bot_token: nil, signing_secret: nil, timeout: 15, open_timeout: 5, max_retries: 3)
        @slack_client = SlackClient.new(
          bot_token: bot_token,
          signing_secret: signing_secret,
          timeout: timeout,
          open_timeout: open_timeout,
          max_retries: max_retries
        )
        @retry_handler = RetryHandler.new(max_attempts: max_retries)
        @thread_fetcher = ThreadFetcher.new(@slack_client, @retry_handler)
        @shortcut_handler = ShortcutHandler.new(@slack_client, @retry_handler)
      end

      # Delegate configuration attributes to slack_client
      def bot_token
        slack_client.bot_token
      end

      def signing_secret
        slack_client.signing_secret
      end

      def timeout
        slack_client.timeout
      end

      def open_timeout
        slack_client.open_timeout
      end

      def max_retries
        slack_client.max_retries
      end

      # Delegate client access to slack_client
      def client
        slack_client.client
      end

      # Delegate webhook validation to slack_client
      def webhook_validator
        slack_client.webhook_validator
      end

      # Delegate retry logic to retry_handler
      def retry_with(&block)
        retry_handler.retry_with(&block)
      end

      # Validate a Slack webhook payload
      # @param payload [Hash, String] The webhook payload
      # @param headers [Hash] The request headers containing signature
      # @return [ThreadAgent::Result] Result object with validated payload or error
      def validate_webhook(payload, headers)
        webhook_validator.validate(payload, headers)
      end

      # Delegate thread fetching to thread_fetcher
      # @param channel_id [String] The Slack channel ID
      # @param thread_ts [String] The timestamp of the parent message
      # @return [ThreadAgent::Result] Result object with thread data or error
      def fetch_thread(channel_id, thread_ts)
        thread_fetcher.fetch_thread(channel_id, thread_ts)
      end

      # Delegate shortcut handling to shortcut_handler
      # @param payload [Hash] The Slack shortcut payload
      # @return [ThreadAgent::Result] Result object with success or error response
      def handle_shortcut(payload)
        shortcut_handler.handle_shortcut(payload)
      end

      # Delegate modal creation to shortcut_handler
      # @param trigger_id [String] The Slack trigger ID for the modal
      # @param workspaces [Array<Hash>] List of available workspaces
      # @param templates [Array<Hash>] List of available templates
      # @return [ThreadAgent::Result] Result object with modal payload or error
      def create_modal(trigger_id, workspaces, templates = [])
        shortcut_handler.create_modal(trigger_id, workspaces, templates)
      end

      # Handle modal submission events
      # @param payload [Hash] The Slack view submission payload
      # @return [ThreadAgent::Result] Result object indicating success or failure
      def handle_modal_submission(payload)
        return ThreadAgent::Result.failure("Invalid payload type") unless payload["type"] == "view_submission"

        Rails.logger.info("Processing modal submission for user: #{payload.dig('user', 'id')}")

        # Extract submitted values for validation
        view = payload["view"]
        state_values = view&.dig("state", "values") || {}

        # Basic validation - ensure we have required modal data
        if view.nil? || state_values.empty?
          return ThreadAgent::Result.failure("Missing modal submission data")
        end

        # Log the submission details for debugging
        Rails.logger.info("Modal state values: #{state_values.inspect}")

        ThreadAgent::Result.success("Modal submission processed successfully")
      rescue StandardError => e
        Rails.logger.error("Error processing modal submission: #{e.message}")
        ThreadAgent::Result.failure("Failed to process modal submission: #{e.message}")
      end
    end
  end
end
