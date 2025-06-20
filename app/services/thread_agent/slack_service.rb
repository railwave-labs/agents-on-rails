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

    # Fetch a thread from a Slack channel
    # @param channel_id [String] The Slack channel ID
    # @param thread_ts [String] The timestamp of the parent message
    # @return [ThreadAgent::Result] Result object with thread data or error
    def fetch_thread(channel_id, thread_ts)
      validate_thread_params!(channel_id, thread_ts)

      begin
        # Get the parent message first
        parent_message = client.conversations_history(
          channel: channel_id,
          latest: thread_ts,
          limit: 1,
          inclusive: true
        ).messages.first

        return ThreadAgent::Result.failure("Parent message not found") unless parent_message

        # Get replies in the thread
        replies = client.conversations_replies(
          channel: channel_id,
          ts: thread_ts
        ).messages

        ThreadAgent::Result.success(format_thread_data(parent_message, replies))
      rescue Slack::Web::Api::Errors::RateLimited => e
        handle_rate_limit(e)
      rescue Slack::Web::Api::Errors::SlackError => e
        ThreadAgent::Result.failure("Slack API error: #{e.message}")
      rescue StandardError => e
        ThreadAgent::Result.failure("Unexpected error: #{e.message}")
      end
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

    def validate_thread_params!(channel_id, thread_ts)
      raise ThreadAgent::SlackError, "Missing channel_id" if channel_id.blank?
      raise ThreadAgent::SlackError, "Missing thread_ts" if thread_ts.blank?
    end

    def format_thread_data(parent, replies)
      {
        channel_id: parent.channel,
        thread_ts: parent.ts,
        parent_message: format_message(parent),
        replies: replies.map { |reply| format_message(reply) }.drop(1) # Drop first message as it's the parent
      }
    end

    def format_message(message)
      {
        user: message.user,
        text: message.text,
        ts: message.ts,
        attachments: message.try(:attachments) || [],
        files: message.try(:files) || []
      }
    end

    def handle_rate_limit(error)
      retry_after = error.response_metadata&.dig("retry_after") || 60
      ThreadAgent::Result.failure(
        "Rate limited by Slack API. Retry after #{retry_after} seconds.",
        retry_after: retry_after
      )
    end
  end
end
