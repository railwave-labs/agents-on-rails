# frozen_string_literal: true

require "test_helper"

class ShortcutFlowTest < ActionDispatch::IntegrationTest
  def setup
    ENV["THREAD_AGENT_SLACK_SIGNING_SECRET"] = "test-secret"
    ENV["THREAD_AGENT_SLACK_BOT_TOKEN"] = "xoxb-test-token"
    ENV["THREAD_AGENT_SLACK_SIGNING_SECRET"] = "test-secret"
    ThreadAgent.reset_configuration!

    @workspace = create(:notion_workspace, slack_team_id: "T123456")
    @database = create(:notion_database, notion_workspace: @workspace)
    @template = create(:template, notion_database: @database)

    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
  end

  def teardown
    ENV.delete("THREAD_AGENT_SLACK_SIGNING_SECRET")
    ENV.delete("THREAD_AGENT_SLACK_BOT_TOKEN")
    ENV.delete("THREAD_AGENT_SLACK_SIGNING_SECRET")
    WebMock.reset!
  end

  def valid_headers(timestamp, body)
    signature = "v0=" + OpenSSL::HMAC.hexdigest("SHA256", "test-secret", "v0:#{timestamp}:#{body}")
    {
      "Content-Type" => "application/json",
      "X-Slack-Request-Timestamp" => timestamp,
      "X-Slack-Signature" => signature
    }
  end

  test "end to end workflow from shortcut to job enqueuing" do
    # Stub external calls to prevent real API calls
    stub_request(:post, /slack\.com/).to_return(body: '{"ok":true}')

    # Test 1: Shortcut request succeeds
    timestamp = Time.now.to_i.to_s
    shortcut_payload = {
      type: "shortcut",
      callback_id: "thread_capture",
      trigger_id: "123.456.abc",
      team: { id: "T123456" },
      user: { id: "U123" }
    }.to_json

    post "/thread_agent/webhooks/slack",
         params: shortcut_payload,
         headers: valid_headers(timestamp, shortcut_payload)
    assert_response :success

    # Test 2: Modal submission enqueues job
    modal_payload = {
      type: "view_submission",
      view: {
        id: "V123456",
        state: {
          values: {
            workspace_select: {
              selected_workspace: {
                selected_option: { value: @workspace.id.to_s }
              }
            },
            template_select: {
              selected_template: {
                selected_option: { value: @template.id.to_s }
              }
            }
          }
        }
      }
    }.to_json

    timestamp2 = (Time.now.to_i + 1).to_s
    post "/thread_agent/webhooks/slack",
         params: modal_payload,
         headers: valid_headers(timestamp2, modal_payload)

    assert_response :success
    assert_enqueued_jobs 1, only: ThreadAgent::ProcessWorkflowJob
  end

  test "handles missing workspace error" do
    timestamp = Time.now.to_i.to_s
    payload = {
      type: "shortcut",
      callback_id: "thread_capture",
      trigger_id: "123.456.abc",
      team: { id: "MISSING" }
    }.to_json

    post "/thread_agent/webhooks/slack",
         params: payload,
         headers: valid_headers(timestamp, payload)
    assert_response :unprocessable_entity
  end
end
