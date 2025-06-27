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
          parent_message = retry_handler.retry_with do
            slack_client.client.conversations_history(
              channel: channel_id,
              latest: thread_ts,
              limit: 1,
              inclusive: true
            ).messages.first
          end

          unless parent_message
            error = ThreadAgent::ValidationError.new(
              "Parent message not found",
              context: {
                component: "thread_fetching",
                channel_id: channel_id,
                thread_ts: thread_ts
              }
            )
            return ThreadAgent::ErrorHandler.to_result(error, service: "slack")
          end

          # Get replies in the thread
          replies = retry_handler.retry_with do
            slack_client.client.conversations_replies(
              channel: channel_id,
              ts: thread_ts
            ).messages
          end

          formatted_data = MessageFormatter.format_thread_data(parent_message, replies)
          ThreadAgent::Result.success(formatted_data)
        rescue ThreadAgent::Error => e
          # Already a standardized error, just convert to result
          ThreadAgent::ErrorHandler.to_result(e, service: "slack")
        rescue StandardError => e
          ThreadAgent::ErrorHandler.to_result(
            e,
            context: {
              component: "thread_fetching",
              channel_id: channel_id,
              thread_ts: thread_ts
            },
            service: "slack"
          )
        end
      end

      private

      def validate_thread_params!(channel_id, thread_ts)
        if channel_id.blank?
          raise ThreadAgent::ValidationError.new(
            "Missing channel_id",
            context: { component: "thread_fetching", thread_ts: thread_ts }
          )
        end

        if thread_ts.blank?
          raise ThreadAgent::ValidationError.new(
            "Missing thread_ts",
            context: { component: "thread_fetching", channel_id: channel_id }
          )
        end
      end
    end
  end
end
