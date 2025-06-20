# frozen_string_literal: true

module ThreadAgent
  class SlackService
    attr_reader :bot_token, :timeout, :open_timeout, :max_retries

    def initialize(bot_token: nil, timeout: 15, open_timeout: 5, max_retries: 3)
      @bot_token = bot_token || ThreadAgent.configuration.slack_bot_token
      @timeout = timeout
      @open_timeout = open_timeout
      @max_retries = max_retries
      validate_configuration!
    end

    def client
      @client ||= initialize_client
    end

    private

    def initialize_client
      Slack::Web::Client.new(token: bot_token).tap do |client|
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
    end
  end
end
