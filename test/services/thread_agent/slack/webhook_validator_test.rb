# frozen_string_literal: true

require "test_helper"

class ThreadAgent::Slack::WebhookValidatorTest < ActiveSupport::TestCase
  def setup
    @signing_secret = "test-signing-secret"
    @validator = ThreadAgent::Slack::WebhookValidator.new(@signing_secret)
    @valid_timestamp = Time.now.to_i.to_s
    @valid_payload = { "type" => "event_callback", "event" => { "type" => "message" } }
    @raw_payload = @valid_payload.to_json
  end

  test "initializes with signing secret" do
    assert_equal @signing_secret, @validator.signing_secret
  end

  test "raises error when signing secret is missing" do
    assert_raises(ThreadAgent::SlackError, /Missing Slack signing secret/) do
      ThreadAgent::Slack::WebhookValidator.new(nil)
    end
  end

  test "raises error when signing secret is empty" do
    assert_raises(ThreadAgent::SlackError, /Missing Slack signing secret/) do
      ThreadAgent::Slack::WebhookValidator.new("")
    end
  end

  test "validate returns success with valid signature and JSON payload" do
    headers = valid_headers
    result = @validator.validate(@raw_payload, headers)

    assert result.success?
    assert_equal @valid_payload, result.data
  end

  test "validate returns success with valid signature and Hash payload" do
    headers = valid_headers(@valid_timestamp, @valid_payload.to_json)
    result = @validator.validate(@valid_payload, headers)

    assert result.success?
    assert_equal @valid_payload, result.data
  end

  test "validate returns failure for invalid signature" do
    invalid_headers = {
      "X-Slack-Request-Timestamp" => @valid_timestamp,
      "X-Slack-Signature" => "v0=invalid-signature"
    }

    result = @validator.validate(@raw_payload, invalid_headers)

    assert result.failure?
    assert_match(/Invalid Slack signature/, result.error)
  end

  test "validate returns failure for expired timestamp" do
    expired_timestamp = (Time.now.to_i - 400).to_s # 400 seconds old (> 5 minutes)
    expired_headers = valid_headers(expired_timestamp, @raw_payload)

    result = @validator.validate(@raw_payload, expired_headers)

    assert result.failure?
    assert_match(/Invalid Slack signature/, result.error)
  end

  test "validate returns failure for missing timestamp header" do
    headers = {
      "X-Slack-Signature" => generate_valid_signature(@valid_timestamp, @raw_payload)
    }

    result = @validator.validate(@raw_payload, headers)

    assert result.failure?
    assert_match(/Invalid Slack signature/, result.error)
  end

  test "validate returns failure for missing signature header" do
    headers = {
      "X-Slack-Request-Timestamp" => @valid_timestamp
    }

    result = @validator.validate(@raw_payload, headers)

    assert result.failure?
    assert_match(/Invalid Slack signature/, result.error)
  end

  test "validate returns failure when payload is missing" do
    result = @validator.validate(nil, valid_headers)

    assert result.failure?
    assert_match(/Missing payload/, result.error)
  end

  test "validate returns failure when headers are missing" do
    result = @validator.validate(@valid_payload, nil)

    assert result.failure?
    assert_match(/Missing headers/, result.error)
  end

  test "validate returns failure for invalid JSON payload" do
    invalid_json = "{ invalid json }"
    headers = valid_headers(@valid_timestamp, invalid_json)

    result = @validator.validate(invalid_json, headers)

    assert result.failure?
    assert_match(/Failed to parse JSON response/, result.error)
  end

  test "validate accepts url_verification payload type" do
    payload = { "type" => "url_verification", "challenge" => "test-challenge" }
    headers = valid_headers(@valid_timestamp, payload.to_json)

    result = @validator.validate(payload, headers)

    assert result.success?
    assert_equal payload, result.data
  end

  test "validate accepts block_actions payload type" do
    payload = { "type" => "block_actions", "actions" => [ { "action_id" => "test" } ] }
    headers = valid_headers(@valid_timestamp, payload.to_json)

    result = @validator.validate(payload, headers)

    assert result.success?
    assert_equal payload, result.data
  end

  test "validate accepts view_submission payload type" do
    payload = { "type" => "view_submission", "view" => { "id" => "test-view-id" } }
    headers = valid_headers(@valid_timestamp, payload.to_json)

    result = @validator.validate(payload, headers)

    assert result.success?
    assert_equal payload, result.data
  end

  test "validate rejects unknown payload type" do
    payload = { "type" => "unknown_type" }
    headers = valid_headers(@valid_timestamp, payload.to_json)

    result = @validator.validate(payload, headers)

    assert result.failure?
    assert_match(/Invalid payload structure/, result.error)
  end

  test "validate rejects url_verification without challenge" do
    payload = { "type" => "url_verification" }
    headers = valid_headers(@valid_timestamp, payload.to_json)

    result = @validator.validate(payload, headers)

    assert result.failure?
    assert_match(/Invalid payload structure/, result.error)
  end

  test "validate rejects event_callback without event" do
    payload = { "type" => "event_callback" }
    headers = valid_headers(@valid_timestamp, payload.to_json)

    result = @validator.validate(payload, headers)

    assert result.failure?
    assert_match(/Invalid payload structure/, result.error)
  end

  test "validate rejects block_actions without actions array" do
    payload = { "type" => "block_actions", "actions" => "not-an-array" }
    headers = valid_headers(@valid_timestamp, payload.to_json)

    result = @validator.validate(payload, headers)

    assert result.failure?
    assert_match(/Invalid payload structure/, result.error)
  end

  private

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
