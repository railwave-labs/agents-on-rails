# frozen_string_literal: true

module ThreadAgent
  module Slack
    class ModalBuilder
      # Build a complete modal payload for thread capture
      # @param workspaces [Array<Hash>] List of available workspaces
      # @param templates [Array<Hash>] List of available templates (optional)
      # @return [Hash] Complete modal payload for Slack API
      def self.build_thread_capture_modal(workspaces, templates = [])
        {
          type: "modal",
          callback_id: "thread_capture_modal",
          title: {
            type: "plain_text",
            text: "Capture Thread"
          },
          submit: {
            type: "plain_text",
            text: "Capture"
          },
          close: {
            type: "plain_text",
            text: "Cancel"
          },
          blocks: build_modal_blocks(workspaces, templates)
        }
      end

      private

      # Build the blocks array for the modal
      # @param workspaces [Array<Hash>] List of available workspaces
      # @param templates [Array<Hash>] List of available templates
      # @return [Array<Hash>] Array of block elements
      def self.build_modal_blocks(workspaces, templates)
        blocks = [
          {
            type: "section",
            text: {
              type: "mrkdwn",
              text: "Select a workspace and template to capture this thread."
            }
          },
          {
            type: "divider"
          },
          build_workspace_selector(workspaces)
        ]

        # Only add template selector if templates are provided
        if templates.present?
          blocks << build_template_selector(templates)
        end

        # Add custom prompt input field
        blocks << build_custom_prompt_input

        blocks
      end

      # Build a workspace selector block
      # @param workspaces [Array<Hash>] List of available workspaces
      # @return [Hash] Input block with workspace selector
      def self.build_workspace_selector(workspaces)
        options = workspaces.map do |workspace|
          {
            text: {
              type: "plain_text",
              text: workspace[:name] || workspace["name"]
            },
            value: (workspace[:id] || workspace["id"]).to_s
          }
        end

        {
          type: "input",
          block_id: "workspace_block",
          element: {
            type: "static_select",
            placeholder: {
              type: "plain_text",
              text: "Select a workspace"
            },
            options: options,
            action_id: "workspace_select"
          },
          label: {
            type: "plain_text",
            text: "Workspace"
          }
        }
      end

      # Build a template selector block
      # @param templates [Array<Hash>] List of available templates
      # @return [Hash] Input block with template selector
      def self.build_template_selector(templates)
        options = templates.map do |template|
          {
            text: {
              type: "plain_text",
              text: template[:name] || template["name"]
            },
            value: (template[:id] || template["id"]).to_s
          }
        end

        {
          type: "input",
          block_id: "template_block",
          element: {
            type: "static_select",
            placeholder: {
              type: "plain_text",
              text: "Select a template"
            },
            options: options,
            action_id: "template_select"
          },
          label: {
            type: "plain_text",
            text: "Template"
          }
        }
      end

      # Build a custom prompt input block
      # @return [Hash] Input block with text area for custom prompt
      def self.build_custom_prompt_input
        {
          type: "input",
          block_id: "custom_prompt_block",
          optional: true,
          element: {
            type: "plain_text_input",
            multiline: true,
            placeholder: {
              type: "plain_text",
              text: "Optional: Add custom instructions for processing this thread..."
            },
            action_id: "custom_prompt_input"
          },
          label: {
            type: "plain_text",
            text: "Custom Prompt (Optional)"
          }
        }
      end
    end
  end
end
