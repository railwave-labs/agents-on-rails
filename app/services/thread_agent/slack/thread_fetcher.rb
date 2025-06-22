# frozen_string_literal: true

module ThreadAgent
  module Slack
    class ThreadFetcher
      attr_reader :slack_client, :retry_handler

      def initialize(slack_client, retry_handler)
        @slack_client = slack_client
        @retry_handler = retry_handler
      end

      # Fetch a thread from a Slack channel
      # @param channel_id [String] The Slack channel ID
      # @param thread_ts [String] The timestamp of the parent message
      # @return [ThreadAgent::Result] Result object with thread data or error
      def fetch_thread(channel_id, thread_ts)
        begin
          validate_thread_params!(channel_id, thread_ts)

          # Get the parent message first
          parent_message = retry_handler.with_retries do
            slack_client.client.conversations_history(
              channel: channel_id,
              latest: thread_ts,
              limit: 1,
              inclusive: true
            ).messages.first
          end

          return ThreadAgent::Result.failure("Parent message not found") unless parent_message

          # Get replies in the thread
          replies = retry_handler.with_retries do
            slack_client.client.conversations_replies(
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

      private

      def validate_thread_params!(channel_id, thread_ts)
        raise ThreadAgent::SlackError, "Missing channel_id" if channel_id.blank?
        raise ThreadAgent::SlackError, "Missing thread_ts" if thread_ts.blank?
      end
    end
  end
end
