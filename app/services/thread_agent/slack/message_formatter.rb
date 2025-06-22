# frozen_string_literal: true

module ThreadAgent
  module Slack
    class MessageFormatter
      # Format thread data for consistent structure
      # @param parent [Object] The parent message object
      # @param replies [Array] Array of reply message objects
      # @return [Hash] Formatted thread data
      def self.format_thread_data(parent, replies)
        {
          channel_id: parent.channel,
          thread_ts: parent.ts,
          parent_message: format_message(parent),
          replies: replies.map { |reply| format_message(reply) }.drop(1) # Drop first message as it's the parent
        }
      end

      # Format a single message for consistent structure
      # @param message [Object] The message object from Slack API
      # @return [Hash] Formatted message data
      def self.format_message(message)
        {
          user: message.user,
          text: message.text,
          ts: message.ts,
          attachments: message.try(:attachments) || [],
          files: message.try(:files) || []
        }
      end
    end
  end
end
