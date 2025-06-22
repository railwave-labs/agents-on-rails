# frozen_string_literal: true

require "test_helper"
require "ostruct"

class ThreadAgent::Slack::WebhookRequestHandlerTest < ActiveSupport::TestCase
  def setup
    @signing_secret = "test-signing-secret"
    @valid_timestamp = Time.now.to_i.to_s
    @valid_payload = { "type" => "event_callback", "event" => { "type" => "message" } }
    @raw_payload = @valid_payload.to_json
  end

  test "successfully processes valid JSON payload" do
    request = mock_request(@raw_payload, valid_headers)
    params = ActionController::Parameters.new

    handler = ThreadAgent::Slack::WebhookRequestHandler.new(request, params, @signing_secret)
    result = handler.process

    assert result.success?
    assert_equal @valid_payload, result.data
  end

  test "successfully processes valid form-encoded payload" do
    slack_payload = { "type" => "block_actions", "actions" => [ { "action_id" => "test" } ] }
    form_data = { payload: slack_payload.to_json }.to_query

    request = mock_request(form_data, valid_headers(@valid_timestamp, form_data), "application/x-www-form-urlencoded")
    params = ActionController::Parameters.new(payload: slack_payload.to_json)

    handler = ThreadAgent::Slack::WebhookRequestHandler.new(request, params, @signing_secret)
    result = handler.process

    assert result.success?
    assert_equal slack_payload, result.data
  end

  test "fails when signing secret is missing" do
    request = mock_request(@raw_payload, valid_headers)
    params = ActionController::Parameters.new

    handler = ThreadAgent::Slack::WebhookRequestHandler.new(request, params, nil)
    result = handler.process

    assert result.failure?
    assert_match(/Missing signing secret/, result.error)
  end

  test "fails when signature headers are missing" do
    request = mock_request(@raw_payload, {})
    params = ActionController::Parameters.new

    handler = ThreadAgent::Slack::WebhookRequestHandler.new(request, params, @signing_secret)
    result = handler.process

    assert result.failure?
    assert_match(/Missing Slack signature headers/, result.error)
  end

  test "fails with invalid signature" do
    invalid_headers = {
      "X-Slack-Request-Timestamp" => @valid_timestamp,
      "X-Slack-Signature" => "v0=invalid-signature"
    }

    request = mock_request(@raw_payload, invalid_headers)
    params = ActionController::Parameters.new

    handler = ThreadAgent::Slack::WebhookRequestHandler.new(request, params, @signing_secret)
    result = handler.process

    assert result.failure?
    assert_match(/Webhook validation failed/, result.error)
  end

  test "fails with expired timestamp" do
    expired_timestamp = (Time.now.to_i - 400).to_s # 400 seconds old
    expired_headers = valid_headers(expired_timestamp, @raw_payload)

    request = mock_request(@raw_payload, expired_headers)
    params = ActionController::Parameters.new

    handler = ThreadAgent::Slack::WebhookRequestHandler.new(request, params, @signing_secret)
    result = handler.process

    assert result.failure?
    assert_match(/Webhook validation failed/, result.error)
  end

  test "fails with invalid JSON payload" do
    invalid_json = "{ invalid json }"
    headers = valid_headers(@valid_timestamp, invalid_json)

    request = mock_request(invalid_json, headers)
    params = ActionController::Parameters.new

    handler = ThreadAgent::Slack::WebhookRequestHandler.new(request, params, @signing_secret)
    result = handler.process

    assert result.failure?
    assert_match(/Failed to parse webhook payload/, result.error)
  end

  test "validates shortcut payload structure" do
    shortcut_payload = { "type" => "shortcut", "callback_id" => "test", "trigger_id" => "trigger" }
    form_data = { payload: shortcut_payload.to_json }.to_query

    request = mock_request(form_data, valid_headers(@valid_timestamp, form_data), "application/x-www-form-urlencoded")
    params = ActionController::Parameters.new(payload: shortcut_payload.to_json)

    handler = ThreadAgent::Slack::WebhookRequestHandler.new(request, params, @signing_secret)
    result = handler.process

    assert result.success?
    assert_equal shortcut_payload, result.data
  end

  test "fails with invalid shortcut payload structure" do
    invalid_shortcut = { "type" => "shortcut" } # missing required fields
    form_data = { payload: invalid_shortcut.to_json }.to_query

    request = mock_request(form_data, valid_headers(@valid_timestamp, form_data), "application/x-www-form-urlencoded")
    params = ActionController::Parameters.new(payload: invalid_shortcut.to_json)

    handler = ThreadAgent::Slack::WebhookRequestHandler.new(request, params, @signing_secret)
    result = handler.process

    assert result.failure?
    assert_match(/Invalid payload structure/, result.error)
  end

  private

  def mock_request(raw_post, headers, content_type = "application/json")
    OpenStruct.new(
      raw_post: raw_post,
      headers: headers,
      content_type: content_type
    )
  end

  def generate_valid_signature(timestamp, raw_body)
    basestring = "v0:#{timestamp}:#{raw_body}"
    "v0=" + OpenSSL::HMAC.hexdigest("SHA256", @signing_secret, basestring)
  end

  def valid_headers(timestamp = @valid_timestamp, raw_body = @raw_payload)
    {
      "X-Slack-Request-Timestamp" => timestamp,
      "X-Slack-Signature" => generate_valid_signature(timestamp, raw_body)
    }
  end
end
