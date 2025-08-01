# frozen_string_literal: true

module ThreadAgent
  module Slack
    class WebhookValidator
      TIMESTAMP_TOLERANCE = 300 # 5 minutes in seconds

      attr_reader :signing_secret

      def initialize(signing_secret)
        @signing_secret = signing_secret
        validate_signing_secret!
      end

      # Validate a Slack webhook payload
      # @param payload [Hash, String] The webhook payload
      # @param headers [Hash] The request headers containing signature
      # @return [ThreadAgent::Result] Result object with validated payload or error
      def validate(payload, headers)
        return ThreadAgent::Result.failure("Missing payload") if payload.blank?
        return ThreadAgent::Result.failure("Missing headers") if headers.blank?

        begin
          # Verify the request signature
          timestamp = headers["X-Slack-Request-Timestamp"]
          signature = headers["X-Slack-Signature"]
          raw_body = payload.is_a?(Hash) ? payload.to_json : payload.to_s

          unless valid_signature?(timestamp, signature, raw_body)
            error = ThreadAgent::SlackAuthError.new(
              "Invalid Slack signature",
              context: {
                component: "webhook_validation",
                timestamp: timestamp,
                signature_present: signature.present?
              }
            )
            return ThreadAgent::ErrorHandler.to_result(error, service: "slack")
          end

          # Parse the payload if it's a string
          parsed_payload = payload.is_a?(Hash) ? payload : JSON.parse(payload)

          # Verify the payload structure
          unless valid_payload_structure?(parsed_payload)
            error = ThreadAgent::ValidationError.new(
              "Invalid payload structure",
              context: {
                component: "webhook_validation",
                payload_type: parsed_payload["type"],
                payload_keys: parsed_payload.keys
              }
            )
            return ThreadAgent::ErrorHandler.to_result(error, service: "slack")
          end

          ThreadAgent::Result.success(parsed_payload)
        rescue JSON::ParserError => e
          ThreadAgent::ErrorHandler.to_result(
            e,
            context: { component: "webhook_validation", raw_body_length: raw_body&.length },
            service: "slack"
          )
        rescue StandardError => e
          ThreadAgent::ErrorHandler.to_result(
            e,
            context: { component: "webhook_validation" },
            service: "slack"
          )
        end
      end

      private

      def validate_signing_secret!
        unless signing_secret.present?
          raise ThreadAgent::SlackAuthError.new(
            "Missing Slack signing secret",
            context: { component: "webhook_validator_initialization" }
          )
        end
      end

      def valid_signature?(timestamp, signature, raw_body)
        return false if timestamp.blank? || signature.blank? || raw_body.blank?

        # Check if the timestamp is too old
        return false if timestamp_expired?(timestamp)

        # Generate the signature
        basestring = "v0:#{timestamp}:#{raw_body}"
        my_signature = "v0=" + OpenSSL::HMAC.hexdigest("SHA256", signing_secret, basestring)

        # Compare signatures using secure comparison
        ActiveSupport::SecurityUtils.secure_compare(my_signature, signature)
      end

      def timestamp_expired?(timestamp)
        Time.now.to_i - timestamp.to_i > TIMESTAMP_TOLERANCE
      end

      def valid_payload_structure?(payload)
        # Basic structure validation
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
    end
  end
end
