# frozen_string_literal: true

module ThreadAgent
  module Slack
    class ShortcutHandler
      attr_reader :slack_client, :retry_handler

      def initialize(slack_client, retry_handler)
        @slack_client = slack_client
        @retry_handler = retry_handler
      end

      # Handle a Slack shortcut event by opening a modal for thread capture
      # @param payload [Hash] The Slack shortcut payload
      # @return [ThreadAgent::Result] Result object with success or error response
      def handle_shortcut(payload)
        # Validate required fields from shortcut payload
        callback_id = payload.dig("callback_id")
        trigger_id = payload.dig("trigger_id")
        team_id = payload.dig("team", "id")

        return ThreadAgent::Result.failure("Missing callback_id") if callback_id.blank?
        return ThreadAgent::Result.failure("Missing trigger_id") if trigger_id.blank?
        return ThreadAgent::Result.failure("Missing team_id") if team_id.blank?

        begin
          # Find the active workspace for this Slack team
          workspace = ThreadAgent::NotionWorkspace.active_for_slack_team(team_id)
          return ThreadAgent::Result.failure("No active workspace found for team") unless workspace

          # Get available templates (all active templates for now)
          templates = ThreadAgent::Template.where(status: :active)

          # Convert workspace and templates to the format expected by ModalBuilder
          workspace_data = [ {
            id: workspace.id,
            name: workspace.name
          } ]

          template_data = templates.map do |template|
            {
              id: template.id,
              name: template.name
            }
          end

          # Extract context for message shortcuts
          context_metadata = extract_shortcut_context(payload)

          # Create and open the modal
          result = create_modal(trigger_id, workspace_data, template_data, context_metadata)

          if result.success?
            ThreadAgent::Result.success({ status: "ok" })
          else
            result
          end
        rescue StandardError => e
          ThreadAgent::Result.failure("Unexpected error: #{e.message}")
        end
      end

      # Create a modal for workspace, database, and template selection
      # @param trigger_id [String] The Slack trigger ID for the modal
      # @param workspaces [Array<Hash>] List of available workspaces
      # @param templates [Array<Hash>] List of available templates
      # @param context_metadata [Hash] Context information from shortcut (channel, message, etc.)
      # @return [ThreadAgent::Result] Result object with modal payload or error
      def create_modal(trigger_id, workspaces, templates = [], context_metadata = {})
        return ThreadAgent::Result.failure("Missing trigger_id") if trigger_id.blank?
        return ThreadAgent::Result.failure("No workspaces available") if workspaces.blank?

        begin
          modal_payload = ModalBuilder.build_thread_capture_modal(workspaces, templates)

          # Add private_metadata with context information
          if context_metadata.present?
            modal_payload[:private_metadata] = JSON.generate(context_metadata)
          end

          response = retry_handler.retry_with do
            slack_client.client.views_open({
              trigger_id: trigger_id,
              view: modal_payload
            })
          end

          ThreadAgent::Result.success(response)
        rescue ThreadAgent::SlackError => e
          ThreadAgent::Result.failure(e.message)
        rescue StandardError => e
          ThreadAgent::Result.failure("Unexpected error: #{e.message}")
        end
      end

      private

      # Extract context information from shortcut payload
      # @param payload [Hash] The Slack shortcut payload
      # @return [Hash] Context metadata including channel_id, thread_ts, etc.
      def extract_shortcut_context(payload)
        context = {}

        # Extract context based on shortcut type
        case payload["type"]
        when "message_action"
          # Message shortcuts include channel and message context
          if payload["channel"]
            context["channel_id"] = payload.dig("channel", "id")
          end

          if payload["message"]
            message = payload["message"]
            context["thread_ts"] = message["ts"]

            # If this message is already in a thread, get the thread_ts from thread_ts field
            # Otherwise, this message will become the parent of a new thread
            if message["thread_ts"].present?
              context["thread_ts"] = message["thread_ts"]
            end
          end

        when "shortcut"
          # Global shortcuts don't have message context
          # For global shortcuts, users would need to specify the channel/thread in the modal
          Rails.logger.info("Global shortcut triggered - no automatic context available")
        end

        Rails.logger.info("Extracted shortcut context: #{context}")
        context
      end
    end
  end
end
