# frozen_string_literal: true

module ThreadAgent
  module Slack
      class Service
    attr_reader :slack_client, :retry_handler, :thread_fetcher, :shortcut_handler, :thread_processor

    def initialize(bot_token: nil, signing_secret: nil, timeout: 15, open_timeout: 5, max_retries: 3)
      @slack_client = SlackClient.new(
        bot_token: bot_token,
        signing_secret: signing_secret,
        timeout: timeout,
        open_timeout: open_timeout,
        max_retries: max_retries
      )

      # Validate client immediately to ensure proper error handling in tests
      # This ensures that validation errors are raised during initialization
      validate_client_initialization!

      @retry_handler = RetryHandler.new(max_attempts: max_retries)
      @thread_fetcher = ThreadFetcher.new(@slack_client, @retry_handler)
      @shortcut_handler = ShortcutHandler.new(@slack_client, @retry_handler)
      @thread_processor = ThreadProcessor.new(self)
    end

      # Delegate configuration attributes to slack_client
      def bot_token
        slack_client.bot_token
      end

      def signing_secret
        slack_client.signing_secret
      end

      def timeout
        slack_client.timeout
      end

      def open_timeout
        slack_client.open_timeout
      end

      def max_retries
        slack_client.max_retries
      end

      # Delegate client access to slack_client
      def client
        slack_client.client
      end

      # Delegate webhook validation to slack_client
      def webhook_validator
        slack_client.webhook_validator
      end

      # Delegate retry logic to retry_handler
      def retry_with(&block)
        retry_handler.retry_with(&block)
      end

      # Validate a Slack webhook payload
      # @param payload [Hash, String] The webhook payload
      # @param headers [Hash] The request headers containing signature
      # @return [ThreadAgent::Result] Result object with validated payload or error
      def validate_webhook(payload, headers)
        webhook_validator.validate(payload, headers)
      end

      # Delegate thread fetching to thread_fetcher
      # @param channel_id [String] The Slack channel ID
      # @param thread_ts [String] The timestamp of the parent message
      # @return [ThreadAgent::Result] Result object with thread data or error
      def fetch_thread(channel_id, thread_ts)
        thread_fetcher.fetch_thread(channel_id, thread_ts)
      end

      # Delegate shortcut handling to shortcut_handler
      # @param payload [Hash] The Slack shortcut payload
      # @return [ThreadAgent::Result] Result object with success or error response
      def handle_shortcut(payload)
        shortcut_handler.handle_shortcut(payload)
      end

      # Delegate modal creation to shortcut_handler
      # @param trigger_id [String] The Slack trigger ID for the modal
      # @param workspaces [Array<Hash>] List of available workspaces
      # @param templates [Array<Hash>] List of available templates
      # @param context_metadata [Hash] Context information from shortcut (channel, message, etc.)
      # @return [ThreadAgent::Result] Result object with modal payload or error
      def create_modal(trigger_id, workspaces, templates = [], context_metadata = {})
        shortcut_handler.create_modal(trigger_id, workspaces, templates, context_metadata)
      end

  # Handle modal submission events
  # @param payload [Hash] The Slack view submission payload
  # @return [ThreadAgent::Result] Result object with workflow_run_id or error
  def handle_modal_submission(payload)
    return ThreadAgent::Result.failure("Invalid payload type") unless payload["type"] == "view_submission"

    Rails.logger.info("Processing modal submission for user: #{payload.dig('user', 'id')}")

    # Extract submitted values for validation
    view = payload["view"]
    state_values = view&.dig("state", "values") || {}

    # Basic validation - ensure we have required modal data
    if view.nil? || state_values.empty?
      return ThreadAgent::Result.failure("Missing modal submission data")
    end

    # Extract workspace and template IDs from the form submission
    workspace_id = state_values.dig("workspace_block", "workspace_select", "selected_option", "value")
    template_id = state_values.dig("template_block", "template_select", "selected_option", "value")
    custom_prompt = state_values.dig("custom_prompt_block", "custom_prompt_input", "value")

    Rails.logger.info("Extracted values - workspace_id: #{workspace_id}, template_id: #{template_id}, custom_prompt: #{custom_prompt.present? ? '[PROVIDED]' : '[NONE]'}")

    # Validate required fields
    return ThreadAgent::Result.failure("Workspace selection is required") if workspace_id.blank?

    # Find the template if provided
    template = nil
    if template_id.present?
      template = ThreadAgent::Template.find_by(id: template_id)
      return ThreadAgent::Result.failure("Selected template not found") unless template
    end

    # Extract Slack context for the workflow run
    private_metadata = view&.dig("private_metadata")
    slack_context = {}

    if private_metadata.present?
      begin
        slack_context = JSON.parse(private_metadata)
      rescue JSON::ParserError
        # If private_metadata is not JSON, treat it as channel_id for backward compatibility
        slack_context = { "channel_id" => private_metadata }
      end
    end

    slack_channel_id = slack_context["channel_id"]
    slack_thread_ts = slack_context["thread_ts"]
    thread_data = slack_context["thread_data"]
    slack_user_id = payload.dig("user", "id")
    slack_team_id = payload.dig("team", "id")

    # Build input_data
    input_data = {
      workspace_id: workspace_id,
      template_id: template_id,
      channel_id: slack_channel_id,
      thread_ts: slack_thread_ts,
      slack_user_id: slack_user_id,
      slack_team_id: slack_team_id,
      custom_prompt: custom_prompt,
      original_payload: payload
    }

    # Include thread_data if provided (avoids needing to fetch from Slack API)
    input_data[:thread_data] = thread_data if thread_data.present?

    # Create workflow run
    workflow_run = ThreadAgent::WorkflowRun.create_for_workflow(
      "thread_capture",
      slack_channel_id: slack_channel_id,
      slack_thread_ts: slack_thread_ts,
      input_data: input_data,
      template: template
    )

    Rails.logger.info("Created workflow_run with ID: #{workflow_run.id}")

    ThreadAgent::Result.success({ workflow_run_id: workflow_run.id })
  rescue StandardError => e
    Rails.logger.error("Error processing modal submission: #{e.message}")
    ThreadAgent::Result.failure("Failed to process modal submission: #{e.message}")
  end

  # Delegate thread processing to thread_processor
  # @param workflow_run [WorkflowRun] The workflow run to process
  # @return [ThreadAgent::Result] Result object with thread data or error
  def process_workflow_input(workflow_run)
    thread_processor.process_workflow_input(workflow_run)
  end

  private

  # Validate client initialization to ensure errors are raised immediately
  def validate_client_initialization!
    # Trigger validation by accessing configuration methods
    # This will cause SlackClient validation errors to be raised during Service initialization
    slack_client.bot_token
    slack_client.signing_secret
  end
      end
  end
end
