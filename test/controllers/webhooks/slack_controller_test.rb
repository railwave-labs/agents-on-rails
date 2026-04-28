# frozen_string_literal: true

require "test_helper"

class Webhooks::SlackControllerTest < ActionDispatch::IntegrationTest
  def setup
    ENV["SLACK_SIGNING_SECRET"] = "test-secret"
  end

  def teardown
    ENV.delete("SLACK_SIGNING_SECRET")
  end

  def valid_headers(timestamp, body)
    signature = "v0=" + OpenSSL::HMAC.hexdigest("SHA256", "test-secret", "v0:#{timestamp}:#{body}")
    {
      "Content-Type" => "application/json",
      "X-Slack-Request-Timestamp" => timestamp,
      "X-Slack-Signature" => signature
    }
  end

  test "handles URL verification" do
    timestamp = Time.now.to_i.to_s
    payload = '{"type":"url_verification","challenge":"test123"}'

    post webhooks_slack_path,
         params: payload,
         headers: valid_headers(timestamp, payload)

    assert_response :ok
    assert_equal '{"challenge":"test123"}', response.body
  end

  test "rejects invalid signature" do
    timestamp = Time.now.to_i.to_s
    payload = '{"type":"event_callback","event":{"type":"message"}}'

    post webhooks_slack_path,
         params: payload,
         headers: {
           "Content-Type" => "application/json",
           "X-Slack-Request-Timestamp" => timestamp,
           "X-Slack-Signature" => "v0=invalid"
         }

    assert_response :unauthorized
  end

  test "handles shortcut events" do
    create(:notion_workspace, slack_team_id: "T123")
    timestamp = Time.now.to_i.to_s
    payload = {
      type: "shortcut",
      callback_id: "thread_capture",
      trigger_id: "123.456",
      team: { id: "T123" }
    }.to_json

    mock_service = mock
    mock_service.expects(:handle_shortcut).returns(Result.success(status: "ok"))
    Slack::Service.expects(:new).returns(mock_service)

    post webhooks_slack_path,
         params: payload,
         headers: valid_headers(timestamp, payload)

    assert_response :ok
  end

  test "handles view submission and enqueues job" do
    timestamp = Time.now.to_i.to_s
    payload = {
      type: "view_submission",
      view: { id: "V123", state: { values: {} } }
    }.to_json

    mock_service = mock
    mock_service.expects(:handle_modal_submission).returns(Result.success("ok"))
    Slack::Service.expects(:new).returns(mock_service)

    assert_enqueued_with(job: Agents::ThreadCapture::ProcessJob) do
      post webhooks_slack_path,
           params: payload,
           headers: valid_headers(timestamp, payload)
    end

    assert_response :ok
    assert_equal "{}", response.body
  end

  test "handles event_callback and dispatches via EventDispatcher" do
    ENV["TRIAGE_ALERT_SLACK_CHANNEL_IDS"] = "C_TRIAGE"
    timestamp = Time.now.to_i.to_s
    payload = {
      type: "event_callback",
      event: {
        type: "message",
        channel: "C_TRIAGE",
        user: "U123",
        text: "something broke",
        ts: "1234567890.123456"
      }
    }.to_json

    assert_enqueued_with(job: Agents::Triage::AnalyzeJob) do
      post webhooks_slack_path,
           params: payload,
           headers: valid_headers(timestamp, payload)
    end

    assert_response :ok
  ensure
    ENV.delete("TRIAGE_ALERT_SLACK_CHANNEL_IDS")
  end

  test "handles service errors gracefully" do
    timestamp = Time.now.to_i.to_s
    payload = {
      type: "shortcut",
      callback_id: "thread_capture",
      trigger_id: "123.456",
      team: { id: "MISSING" }
    }.to_json

    mock_service = mock
    mock_service.expects(:handle_shortcut).returns(Result.failure("Not found"))
    Slack::Service.expects(:new).returns(mock_service)

    post webhooks_slack_path,
         params: payload,
         headers: valid_headers(timestamp, payload)

    assert_response :unprocessable_entity
  end
end
