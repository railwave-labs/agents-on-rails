# frozen_string_literal: true

module ThreadAgent
  module Notion
    class PageBuilder
      attr_reader :thread_data, :workflow_run, :openai_data

      def initialize(thread_data, workflow_run, openai_data)
        @thread_data = thread_data
        @workflow_run = workflow_run
        @openai_data = openai_data
      end

      def build_properties
        properties = {}

        # Build dynamic title from parent message
        properties["Name"] = build_dynamic_title

        # Add Slack metadata
        properties["Channel"] = thread_data[:channel_id] if thread_data[:channel_id]
        properties["Thread TS"] = thread_data[:thread_ts] if thread_data[:thread_ts]

        # Add participant information
        participants = extract_participants
        properties["Participants"] = participants if participants.any?

        # Add message statistics
        properties["Reply Count"] = thread_data[:replies]&.length || 0

        # Add workflow metadata
        properties["Workflow ID"] = workflow_run.id.to_s
        properties["Template"] = workflow_run.template&.name || "Unknown"
        properties["Status"] = "Completed"
        properties["Created"] = Time.current

        # Add AI model information
        properties["AI Model"] = openai_data[:model] if openai_data[:model]
        properties["Processed At"] = Time.current

        properties
      end

      def build_content
        content = []

        # Main heading
        content << {
          type: "heading_1",
          content: "Slack Thread Analysis"
        }

        # Thread overview section
        add_thread_overview(content)

        # AI analysis section
        add_ai_analysis(content) if openai_data[:content]

        # Metadata section
        add_metadata_section(content)

        content
      end

      private

      def build_dynamic_title
        # Try to use parent message as title
        if thread_data[:parent_message] && thread_data[:parent_message][:text]
          title = thread_data[:parent_message][:text]
            .gsub(/\n+/, " ")          # Replace newlines with spaces
            .gsub(/\s+/, " ")          # Collapse multiple spaces
            .strip                     # Remove leading/trailing whitespace
            .truncate(100)             # Limit length

          return title if title.present?
        end

        # Fallback to workflow name with timestamp
        workflow_name = workflow_run.workflow_name || "Thread Analysis"
        "#{workflow_name} - #{Time.current.strftime('%Y-%m-%d %H:%M')}"
      end

      def extract_participants
        participants = []

        # Add parent message user
        if thread_data[:parent_message] && thread_data[:parent_message][:user]
          participants << thread_data[:parent_message][:user]
        end

        # Add reply users
        if thread_data[:replies]
          thread_data[:replies].each do |reply|
            if reply[:user] && !participants.include?(reply[:user])
              participants << reply[:user]
            end
          end
        end

        participants.uniq
      end

      def add_thread_overview(content)
        content << {
          type: "heading_2",
          content: "Thread Overview"
        }

        # Add parent message
        if thread_data[:parent_message]
          content << {
            type: "heading_3",
            content: "Original Message"
          }

          parent_text = thread_data[:parent_message][:text] || "No text content"
          content << parent_text

          if thread_data[:parent_message][:user]
            content << "**User:** #{thread_data[:parent_message][:user]}"
          end
        end

        # Add replies section if present
        if thread_data[:replies]&.any?
          content << {
            type: "heading_3",
            content: "Thread Replies (#{thread_data[:replies].length})"
          }

          thread_data[:replies].each_with_index do |reply, index|
            content << {
              type: "heading_3",
              content: "Reply #{index + 1}"
            }

            reply_text = reply[:text] || "No text content"
            content << reply_text

            content << "**User:** #{reply[:user]}" if reply[:user]

            # Add divider between replies
            content << "---" unless index == thread_data[:replies].length - 1
          end
        end
      end

      def add_ai_analysis(content)
        content << {
          type: "heading_2",
          content: "AI Analysis"
        }

        # Use the content processor to structure AI content
        ai_content_blocks = ContentProcessor.process_ai_content(openai_data[:content])
        content.concat(ai_content_blocks)
      end

      def add_metadata_section(content)
        content << {
          type: "heading_2",
          content: "Processing Metadata"
        }

        metadata_info = [
          "**Processed:** #{Time.current.strftime('%Y-%m-%d %H:%M:%S %Z')}",
          "**Channel ID:** #{thread_data[:channel_id]}",
          "**Thread TS:** #{thread_data[:thread_ts]}",
          "**Total Messages:** #{(thread_data[:replies]&.length || 0) + 1}"
        ]

        metadata_info << "**AI Model:** #{openai_data[:model]}" if openai_data[:model]

        metadata_info.each { |info| content << info }
      end
    end
  end
end
