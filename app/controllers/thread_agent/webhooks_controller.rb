class ThreadAgent::WebhooksController < ApplicationController
  # Disable CSRF token verification for webhook endpoints
  skip_before_action :verify_authenticity_token, only: :slack

  def slack
    # Validate webhook request using service object
    handler = ThreadAgent::Slack::WebhookRequestHandler.new(
      request,
      params,
      ENV["THREAD_AGENT_SLACK_SIGNING_SECRET"]
    )

    result = handler.process

    unless result.success?
      head :unauthorized
      return
    end

    @payload = result.data

    # Process webhook payload based on type
    case @payload["type"]
    when "url_verification"
      render json: { challenge: @payload["challenge"] }
    when "shortcut", "message_action"
      handle_shortcut
    when "event_callback"
      handle_event
    when "block_actions"
      handle_block_actions
    when "view_submission"
      handle_view_submission
    else
      head :ok
    end
  end

  private

  def handle_shortcut
    service = ThreadAgent::Slack::Service.new
    result = service.handle_shortcut(@payload)

    if result.success?
      render json: result.data, status: :ok
    else
      render json: { error: result.error }, status: :unprocessable_entity
    end
  end

  def handle_event
    # TODO: Implement event handling
    head :ok
  end

  def handle_block_actions
    # TODO: Implement block actions handling
    head :ok
  end

  def handle_view_submission
    Rails.logger.info("Modal submission payload: #{@payload.inspect}")

    service = ThreadAgent::Slack::Service.new
    result = service.handle_modal_submission(@payload)

    if result.success?
      # Extract the workflow_run_id from the service result
      workflow_run_id = result.data[:workflow_run_id]

      # Queue the workflow processing job with the correct workflow_run_id
      ThreadAgent::ProcessWorkflowJob.perform_later(workflow_run_id)

      # Respond with empty JSON per Slack spec
      render json: {}, status: :ok
    else
      Rails.logger.error("Modal submission handling failed: #{result.error}")
      render json: { error: result.error }, status: :unprocessable_entity
    end
  end
end
