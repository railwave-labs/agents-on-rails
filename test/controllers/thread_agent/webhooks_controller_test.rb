require "test_helper"

class ThreadAgent::WebhooksControllerTest < ActionDispatch::IntegrationTest
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

    post thread_agent_webhooks_slack_path,
         params: payload,
         headers: valid_headers(timestamp, payload)

    assert_response :ok
    assert_equal '{"challenge":"test123"}', response.body
  end

  test "rejects invalid signature" do
    timestamp = Time.now.to_i.to_s
    payload = '{"type":"event_callback","event":{"type":"message"}}'

    post thread_agent_webhooks_slack_path,
         params: payload,
         headers: {
           "Content-Type" => "application/json",
           "X-Slack-Request-Timestamp" => timestamp,
           "X-Slack-Signature" => "v0=invalid"
         }

    assert_response :unauthorized
  end

  test "handles shortcut events" do
    workspace = create(:notion_workspace, slack_team_id: "T123")
    timestamp = Time.now.to_i.to_s
    payload = {
      type: "shortcut",
      callback_id: "thread_capture",
      trigger_id: "123.456",
      team: { id: "T123" }
    }.to_json

    # Mock service to avoid external calls
    mock_service = mock
    mock_service.expects(:handle_shortcut).returns(ThreadAgent::Result.success(status: "ok"))
    ThreadAgent::Slack::Service.expects(:new).returns(mock_service)

    post thread_agent_webhooks_slack_path,
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

    # Mock service to return success
    mock_service = mock
    mock_service.expects(:handle_modal_submission).returns(ThreadAgent::Result.success("ok"))
    ThreadAgent::Slack::Service.expects(:new).returns(mock_service)

    assert_enqueued_with(job: ThreadAgent::ProcessWorkflowJob) do
      post thread_agent_webhooks_slack_path,
           params: payload,
           headers: valid_headers(timestamp, payload)
    end

    assert_response :ok
    assert_equal "{}", response.body
  end

  test "handles service errors gracefully" do
    timestamp = Time.now.to_i.to_s
    payload = {
      type: "shortcut",
      callback_id: "thread_capture",
      trigger_id: "123.456",
      team: { id: "MISSING" }
    }.to_json

    # Mock service to return error
    mock_service = mock
    mock_service.expects(:handle_shortcut).returns(ThreadAgent::Result.failure("Not found"))
    ThreadAgent::Slack::Service.expects(:new).returns(mock_service)

    post thread_agent_webhooks_slack_path,
         params: payload,
         headers: valid_headers(timestamp, payload)

    assert_response :unprocessable_entity
  end
end
