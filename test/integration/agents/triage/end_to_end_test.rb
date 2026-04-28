# frozen_string_literal: true

require "test_helper"
require_dependency "anthropic/error"

class Agents::Triage::EndToEndTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  ALERT_CHANNEL   = "C_TRIAGE_E2E"
  ALERT_MESSAGE   = "Error rate spiked on checkout. Orders failing with nil pointer."
  ALERT_TS        = "1234567890.123456"
  SIGNING_SECRET  = "e2e-test-secret"

  TRIAGE_JSON = <<~JSON.strip
    {
      "severity": "high",
      "hypothesis": "Nil pointer in CartService#total — missing nil guard on user.cart attribute",
      "suggested_next_step": "Add nil check in CartService#total and deploy hotfix",
      "context_links": ["https://sentry.io/issues/e2e-999"],
      "confidence": 0.9
    }
  JSON

  ANTHROPIC_RESPONSE = {
    "id"           => "msg_e2e_test",
    "type"         => "message",
    "role"         => "assistant",
    "model"        => "claude-sonnet-4-5",
    "stop_reason"  => "end_turn",
    "stop_sequence" => nil,
    "content"      => [
      {
        "type"        => "mcp_tool_use",
        "server_name" => "sentry",
        "name"        => "get_issue",
        "input"       => { "issue_id" => "e2e-999" }
      },
      {
        "type"        => "mcp_tool_result",
        "tool_use_id" => "tu_e2e_001",
        "is_error"    => false,
        "content"     => [{ "type" => "text", "text" => "Found nil pointer in CartService" }]
      },
      {
        "type" => "text",
        "text" => TRIAGE_JSON
      }
    ],
    "usage" => { "input_tokens" => 500, "output_tokens" => 120 }
  }.freeze

  def setup
    ENV["SLACK_SIGNING_SECRET"]           = SIGNING_SECRET
    ENV["THREAD_AGENT_SLACK_BOT_TOKEN"]   = "xoxb-e2e-test"
    ENV["THREAD_AGENT_SLACK_SIGNING_SECRET"] = SIGNING_SECRET
    ENV["TRIAGE_ALERT_SLACK_CHANNEL_IDS"] = ALERT_CHANNEL
    ENV["ANTHROPIC_API_KEY"]              = "sk-ant-e2e-test"
    ENV["ANTHROPIC_MODEL"]                = "claude-sonnet-4-5"
    ENV["TRIAGE_ESCALATION_SLACK_USER_ID"] = "U_ONCALL_E2E"
    AppConfig.reset_from_env!

    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs

    stub_anthropic_api
    stub_slack_post_message
  end

  def teardown
    %w[
      SLACK_SIGNING_SECRET THREAD_AGENT_SLACK_BOT_TOKEN THREAD_AGENT_SLACK_SIGNING_SECRET
      TRIAGE_ALERT_SLACK_CHANNEL_IDS ANTHROPIC_API_KEY ANTHROPIC_MODEL TRIAGE_ESCALATION_SLACK_USER_ID
    ].each { |k| ENV.delete(k) }
    AppConfig.reset_from_env!
    WebMock.reset!
  end

  def stub_anthropic_api
    stub_request(:post, %r{api\.anthropic\.com.*messages})
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body:    ANTHROPIC_RESPONSE.to_json
      )
  end

  def stub_slack_post_message
    stub_request(:post, %r{slack\.com/api/chat\.postMessage})
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body:    { "ok" => true, "ts" => "9999999999.000001" }.to_json
      )
  end

  def valid_headers(timestamp, body)
    signature = "v0=" + OpenSSL::HMAC.hexdigest("SHA256", SIGNING_SECRET, "v0:#{timestamp}:#{body}")
    {
      "Content-Type"              => "application/json",
      "X-Slack-Request-Timestamp" => timestamp,
      "X-Slack-Signature"         => signature
    }
  end

  def event_payload
    {
      type:  "event_callback",
      event: {
        type:    "message",
        channel: ALERT_CHANNEL,
        user:    "U_ENGINEER",
        text:    ALERT_MESSAGE,
        ts:      ALERT_TS
      }
    }.to_json
  end

  test "signed event_callback triggers triage pipeline and produces completed AgentRun" do
    timestamp = Time.now.to_i.to_s
    payload   = event_payload

    assert_enqueued_with(job: Agents::Triage::AnalyzeJob) do
      post webhooks_slack_path,
           params: payload,
           headers: valid_headers(timestamp, payload)
    end
    assert_response :ok

    assert_difference("AgentRun.count", 1) do
      perform_enqueued_jobs
    end

    run = AgentRun.last
    assert_equal "triage", run.kind
    assert_equal "completed", run.status
    assert_equal ALERT_CHANNEL, run.slack_channel_id
    assert_equal ALERT_TS, run.slack_thread_ts
  end

  test "AgentRun has correct step trail after triage" do
    timestamp = Time.now.to_i.to_s
    payload   = event_payload

    post webhooks_slack_path,
         params: payload,
         headers: valid_headers(timestamp, payload)

    perform_enqueued_jobs

    step_names = AgentRun.last.steps.map { |s| s["name"] }
    assert_includes step_names, "triage_started"
    assert_includes step_names, "mcp_tool_use"
    assert_includes step_names, "mcp_tool_result"
    assert_includes step_names, "usage"
    assert_includes step_names, "triage_parsed"
    assert_includes step_names, "slack_reply_posted"
  end

  test "output_data matches parsed triage payload" do
    timestamp = Time.now.to_i.to_s
    payload   = event_payload

    post webhooks_slack_path,
         params: payload,
         headers: valid_headers(timestamp, payload)

    perform_enqueued_jobs

    output = AgentRun.last.output_data
    assert_equal "high", output["severity"]
    assert_equal 0.9, output["confidence"]
    assert_includes output["context_links"], "https://sentry.io/issues/e2e-999"
  end

  test "chat.postMessage is called with correct thread_ts and mentions escalation user for high severity" do
    timestamp = Time.now.to_i.to_s
    payload   = event_payload

    post webhooks_slack_path,
         params: payload,
         headers: valid_headers(timestamp, payload)

    perform_enqueued_jobs

    assert_requested(:post, %r{slack\.com/api/chat\.postMessage}) do |req|
      body = URI.decode_www_form(req.body).to_h
      body["thread_ts"] == ALERT_TS && body["text"].to_s.include?("<@U_ONCALL_E2E>")
    end
  end

  test "unsigned event_callback returns 401 and no job is enqueued" do
    timestamp = Time.now.to_i.to_s
    payload   = event_payload

    assert_no_enqueued_jobs do
      post webhooks_slack_path,
           params: payload,
           headers: {
             "Content-Type"              => "application/json",
             "X-Slack-Request-Timestamp" => timestamp,
             "X-Slack-Signature"         => "v0=invalid_signature"
           }
    end

    assert_response :unauthorized
  end
end
