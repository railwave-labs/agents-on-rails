# frozen_string_literal: true

module ThreadAgent
  module Slack
    class WebhookRequestHandler
      attr_reader :request, :params, :signing_secret

      def initialize(request, params, signing_secret)
        @request = request
        @params = params
        @signing_secret = signing_secret
      end

      def process
        return failure_result("Missing signing secret") unless signing_secret.present?

        # Parse the payload from request
        parse_result = parse_payload
        return parse_result unless parse_result.success?

        # Verify the signature
        signature_result = verify_signature(parse_result.data[:raw_body], parse_result.data[:payload])
        return signature_result unless signature_result.success?

        # Return successful result with validated payload
        ThreadAgent::Result.success(parse_result.data[:payload])
      end

      private

      def parse_payload
        raw_body = request.raw_post

        # Parse JSON payload - Slack sends payload in different formats
        payload = if params[:payload].present?
                    # Form-encoded payload (typical for interactive components)
                    JSON.parse(params[:payload])
        else
                    # Direct JSON body (typical for event subscriptions)
                    JSON.parse(raw_body) if raw_body.present?
        end

        ThreadAgent::Result.success({ raw_body: raw_body, payload: payload })
      rescue JSON::ParserError => e
        failure_result("Failed to parse webhook payload: #{e.message}")
      end

      def verify_signature(raw_body, payload)
        timestamp = request.headers["X-Slack-Request-Timestamp"]
        signature = request.headers["X-Slack-Signature"]

        return failure_result("Missing Slack signature headers") unless timestamp.present? && signature.present?

        if params[:payload].present?
          # For form-encoded payloads, verify signature against raw body
          return failure_result("Invalid Slack signature") unless valid_signature?(timestamp, signature, raw_body)

          # Validate payload structure separately
          return failure_result("Invalid payload structure") unless valid_payload_structure?(payload)
        else
          # For direct JSON payloads, use the existing WebhookValidator
          validator = WebhookValidator.new(signing_secret)

          slack_headers = {
            "X-Slack-Request-Timestamp" => timestamp,
            "X-Slack-Signature" => signature
          }

          result = validator.validate(raw_body, slack_headers)
          return failure_result("Webhook validation failed: #{result.error}") unless result.success?
        end

        ThreadAgent::Result.success(true)
      end

      def valid_signature?(timestamp, signature, raw_body)
        return false if timestamp.blank? || signature.blank? || raw_body.blank?

        # Check if the timestamp is too old (5 minutes tolerance)
        return false if Time.now.to_i - timestamp.to_i > 300

        # Generate the signature
        basestring = "v0:#{timestamp}:#{raw_body}"
        my_signature = "v0=" + OpenSSL::HMAC.hexdigest("SHA256", signing_secret, basestring)

        # Compare signatures using secure comparison
        ActiveSupport::SecurityUtils.secure_compare(my_signature, signature)
      end

      def valid_payload_structure?(payload)
        return false unless payload.is_a?(Hash)

        # Check for required fields based on payload type
        case payload["type"]
        when "url_verification"
          payload["challenge"].present?
        when "event_callback"
          payload["event"].present? && payload["event"]["type"].present?
        when "block_actions"
          payload["actions"].present? && payload["actions"].is_a?(Array)
        when "view_submission"
          payload["view"].present? && payload["view"]["id"].present?
        when "shortcut"
          payload["callback_id"].present? && payload["trigger_id"].present?
        else
          # Unknown payload type is considered invalid
          false
        end
      end

      def failure_result(message)
        Rails.logger.warn "Slack webhook: #{message}"
        ThreadAgent::Result.failure(message)
      end
    end
  end
end
