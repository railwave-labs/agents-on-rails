# frozen_string_literal: true

module ThreadAgent
  module Openai
    class MessageBuilder
      DEFAULT_SYSTEM_PROMPT = "You are an expert assistant. Summarize the following Slack thread, highlighting key decisions, action items, and main discussion points. Use bullet points for clarity. Exclude greetings and unrelated chatter."

      # Build messages array for OpenAI API
      # @param template [Template, nil] Optional template for custom system prompt
      # @param thread_data [Hash] Slack thread data with parent_message, replies, etc.
      # @param custom_prompt [String, nil] Optional custom prompt from user input
      # @return [Array<Hash>] Array of message hashes for OpenAI API
      def self.build_messages(template: nil, thread_data:, custom_prompt: nil)
        system_content = determine_system_prompt(template, custom_prompt)
        user_content = build_user_content(thread_data)

        [
          { role: "system", content: system_content },
          { role: "user", content: user_content }
        ]
      end

      # Generate a Slack permalink for a thread
      # @param channel_id [String] Slack channel ID
      # @param thread_ts [String] Thread timestamp
      # @return [String] Slack permalink URL
      def self.slack_permalink(channel_id, thread_ts)
        "https://slack.com/app_redirect?channel=#{channel_id}&message_ts=#{thread_ts}"
      end

      private_class_method

      # Determine which system prompt to use based on parameters
      # @param template [Template, nil] Optional template
      # @param custom_prompt [String, nil] Optional custom prompt
      # @return [String] System prompt to use
      def self.determine_system_prompt(template, custom_prompt)
        return custom_prompt if custom_prompt.present?
        return template.content if template&.respond_to?(:content) && template.content.present?

        DEFAULT_SYSTEM_PROMPT
      end

      # Build user content from thread data
      # @param thread_data [Hash] Slack thread data
      # @return [String] Formatted user content
      def self.build_user_content(thread_data)
        content = []

        # Add Slack permalink for easy reference
        if thread_data[:channel_id] && thread_data[:thread_ts]
          permalink = slack_permalink(thread_data[:channel_id], thread_data[:thread_ts])
          content << "**Thread Link:** #{permalink}"
          content << ""
        end

        # Add parent message
        parent = thread_data[:parent_message]
        content << "**Original Message:**"
        content << "User: #{parent[:user]}"
        content << "Message: #{parent[:text]}"
        content << "Timestamp: #{parent[:ts]}"

        # Add replies if present
        if thread_data[:replies]&.any?
          content << ""
          content << "**Thread Replies:**"
          thread_data[:replies].each_with_index do |reply, index|
            content << "#{index + 1}. User: #{reply[:user]}"
            content << "   Message: #{reply[:text]}"
            content << "   Timestamp: #{reply[:ts]}"
          end
        end

        # Add metadata
        content << ""
        content << "**Thread Metadata:**"
        content << "Channel ID: #{thread_data[:channel_id]}"
        content << "Thread Timestamp: #{thread_data[:thread_ts]}"

        content.join("\n")
      end
    end
  end
end
