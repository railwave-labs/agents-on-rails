# frozen_string_literal: true

module ThreadAgent
  module Slack
    class SlackClient
      attr_reader :bot_token, :signing_secret, :timeout, :open_timeout, :max_retries

      def initialize(bot_token: nil, signing_secret: nil, timeout: 15, open_timeout: 5, max_retries: 3)
        @bot_token = bot_token || ThreadAgent.configuration.slack_bot_token
        @signing_secret = signing_secret || ThreadAgent.configuration.slack_signing_secret
        @timeout = timeout
        @open_timeout = open_timeout
        @max_retries = max_retries

        validate_configuration!
      end

      def client
        @client ||= initialize_client
      end

      def webhook_validator
        @webhook_validator ||= WebhookValidator.new(@signing_secret)
      end

      private

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
        error = ThreadAgent::ErrorHandler.standardize_error(
          e,
          context: { component: "slack_client_initialization" },
          service: "slack"
        )
        raise error
      end

      def validate_configuration!
        unless bot_token.present?
          raise ThreadAgent::SlackAuthError.new(
            "Missing Slack bot token",
            context: { component: "slack_client_validation" }
          )
        end

        unless signing_secret.present?
          raise ThreadAgent::SlackAuthError.new(
            "Missing Slack signing secret",
            context: { component: "slack_client_validation" }
          )
        end
      end
    end
  end
end
