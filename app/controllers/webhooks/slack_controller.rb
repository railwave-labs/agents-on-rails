# frozen_string_literal: true

module Webhooks
  class SlackController < ApplicationController
    skip_before_action :verify_authenticity_token, only: :create

    def create
      handler = Slack::WebhookRequestHandler.new(
        request,
        params,
        ENV["SLACK_SIGNING_SECRET"]
      )

      result = handler.process

      unless result.success?
        head :unauthorized
        return
      end

      @payload = result.data

      case @payload["type"]
      when "url_verification"
        render json: { challenge: @payload["challenge"] }
      when "shortcut"
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
      service = Slack::Service.new
      result = service.handle_shortcut(@payload)

      if result.success?
        render json: result.data, status: :ok
      else
        render json: { error: result.error }, status: :unprocessable_entity
      end
    end

    def handle_event
      result = Slack::EventDispatcher.dispatch(@payload)
      Rails.logger.info("Slack event dispatch: #{result.data}")
      head :ok
    end

    def handle_block_actions
      head :ok
    end

    def handle_view_submission
      Rails.logger.info("Modal submission payload: #{@payload.inspect}")

      service = Slack::Service.new
      result = service.handle_modal_submission(@payload)

      if result.success?
        Agents::ThreadCapture::ProcessJob.perform_later(@payload)
        render json: {}, status: :ok
      else
        Rails.logger.error("Modal submission handling failed: #{result.error}")
        render json: { error: result.error }, status: :unprocessable_entity
      end
    end
  end
end
