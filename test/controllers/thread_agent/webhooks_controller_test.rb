require "test_helper"

class ThreadAgent::WebhooksControllerTest < ActionDispatch::IntegrationTest
  def setup
    @signing_secret = "test-signing-secret"
    @valid_timestamp = Time.now.to_i.to_s
    @valid_payload = '{"type":"event_callback","event":{"type":"message","text":"test"}}'
  end

  def generate_valid_signature(timestamp, raw_body, secret = @signing_secret)
    basestring = "v0:#{timestamp}:#{raw_body}"
    "v0=" + OpenSSL::HMAC.hexdigest("SHA256", secret, basestring)
  end

  def valid_headers(timestamp = @valid_timestamp, raw_body = @valid_payload)
    {
      "Content-Type" => "application/json",
      "X-Slack-Request-Timestamp" => timestamp,
      "X-Slack-Signature" => generate_valid_signature(timestamp, raw_body)
    }
  end

  test "slack webhook returns 200 OK with valid signature" do
    ENV["SLACK_SIGNING_SECRET"] = @signing_secret

    post thread_agent_webhooks_slack_path,
         params: @valid_payload,
         headers: valid_headers

    assert_response :ok

    ENV.delete("SLACK_SIGNING_SECRET")
  end

  test "slack webhook handles URL verification" do
    ENV["SLACK_SIGNING_SECRET"] = @signing_secret

    url_verification_payload = '{"type":"url_verification","challenge":"test-challenge"}'
    headers = valid_headers(@valid_timestamp, url_verification_payload)

    post thread_agent_webhooks_slack_path,
         params: url_verification_payload,
         headers: headers

    assert_response :ok
    assert_equal '{"challenge":"test-challenge"}', response.body

    ENV.delete("SLACK_SIGNING_SECRET")
  end

  test "slack webhook returns 401 with invalid signature" do
    ENV["SLACK_SIGNING_SECRET"] = @signing_secret

    invalid_headers = {
      "Content-Type" => "application/json",
      "X-Slack-Request-Timestamp" => @valid_timestamp,
      "X-Slack-Signature" => "v0=invalid-signature"
    }

    post thread_agent_webhooks_slack_path,
         params: @valid_payload,
         headers: invalid_headers

    assert_response :unauthorized

    ENV.delete("SLACK_SIGNING_SECRET")
  end

  test "slack webhook returns 401 with missing timestamp header" do
    ENV["SLACK_SIGNING_SECRET"] = @signing_secret

    headers_without_timestamp = {
      "Content-Type" => "application/json",
      "X-Slack-Signature" => generate_valid_signature(@valid_timestamp, @valid_payload)
    }

    post thread_agent_webhooks_slack_path,
         params: @valid_payload,
         headers: headers_without_timestamp

    assert_response :unauthorized

    ENV.delete("SLACK_SIGNING_SECRET")
  end

  test "slack webhook returns 401 with missing signature header" do
    ENV["SLACK_SIGNING_SECRET"] = @signing_secret

    headers_without_signature = {
      "Content-Type" => "application/json",
      "X-Slack-Request-Timestamp" => @valid_timestamp
    }

    post thread_agent_webhooks_slack_path,
         params: @valid_payload,
         headers: headers_without_signature

    assert_response :unauthorized

    ENV.delete("SLACK_SIGNING_SECRET")
  end

  test "slack webhook returns 401 with expired timestamp" do
    ENV["SLACK_SIGNING_SECRET"] = @signing_secret

    # Timestamp from more than 5 minutes ago
    expired_timestamp = (Time.now.to_i - 400).to_s
    expired_headers = valid_headers(expired_timestamp, @valid_payload)

    post thread_agent_webhooks_slack_path,
         params: @valid_payload,
         headers: expired_headers

    assert_response :unauthorized

    ENV.delete("SLACK_SIGNING_SECRET")
  end

  test "slack webhook returns 401 when SLACK_SIGNING_SECRET is missing" do
    ENV.delete("SLACK_SIGNING_SECRET")

    post thread_agent_webhooks_slack_path,
         params: @valid_payload,
         headers: valid_headers

    assert_response :unauthorized
  end

  test "slack webhook processes form-encoded payload with valid signature" do
    ENV["SLACK_SIGNING_SECRET"] = @signing_secret

    # Use a valid payload type that passes WebhookValidator structure check
    slack_payload = {
      type: "block_actions",
      actions: [ { action_id: "test_action", value: "test" } ]
    }.to_json

    form_params = { payload: slack_payload }
    raw_body = form_params.to_query

    headers = {
      "Content-Type" => "application/x-www-form-urlencoded",
      "X-Slack-Request-Timestamp" => @valid_timestamp,
      "X-Slack-Signature" => generate_valid_signature(@valid_timestamp, raw_body)
    }

    post thread_agent_webhooks_slack_path,
         params: form_params,
         headers: headers

    assert_response :ok

    ENV.delete("SLACK_SIGNING_SECRET")
  end

  test "slack webhook bypasses CSRF protection" do
    ENV["SLACK_SIGNING_SECRET"] = @signing_secret

    # This test ensures no CSRF token is required (only Slack signature)
    post thread_agent_webhooks_slack_path,
         params: @valid_payload,
         headers: valid_headers

    assert_response :ok
    # If CSRF was enabled, this would return 422 Unprocessable Entity

    ENV.delete("SLACK_SIGNING_SECRET")
  end

  test "slack webhook handles empty payload gracefully with valid signature" do
    ENV["SLACK_SIGNING_SECRET"] = @signing_secret

    empty_payload = ""
    headers = valid_headers(@valid_timestamp, empty_payload)
    headers["Content-Type"] = "application/json"

    post thread_agent_webhooks_slack_path,
         params: empty_payload,
         headers: headers

    # Should return 401 because empty payload fails validation
    assert_response :unauthorized

    ENV.delete("SLACK_SIGNING_SECRET")
  end

    test "slack webhook handles shortcut events" do
    ENV["SLACK_SIGNING_SECRET"] = @signing_secret

    # Create test workspace
    workspace = create(:notion_workspace, slack_team_id: "T123456")

    shortcut_payload = {
      type: "shortcut",
      callback_id: "thread_capture",
      trigger_id: "1234567890.123456.abcdef",
      team: {
        id: "T123456"
      },
      user: {
        id: "U123456"
      }
    }.to_json

    headers = valid_headers(@valid_timestamp, shortcut_payload)

    # Mock only the service to avoid making actual API calls to Slack
    mock_service = mock
    mock_result = ThreadAgent::Result.success({ status: "ok" })
    mock_service.expects(:handle_shortcut).with(instance_of(Hash)).returns(mock_result)

    ThreadAgent::Slack::Service.expects(:new).returns(mock_service)

    post thread_agent_webhooks_slack_path,
         params: shortcut_payload,
         headers: headers

    assert_response :ok
    response_data = JSON.parse(response.body)
    assert_equal "ok", response_data["status"]

    ENV.delete("SLACK_SIGNING_SECRET")
  end

    test "slack webhook handles shortcut events with service error" do
    ENV["SLACK_SIGNING_SECRET"] = @signing_secret

    shortcut_payload = {
      type: "shortcut",
      callback_id: "thread_capture",
      trigger_id: "1234567890.123456.abcdef",
      team: {
        id: "T123456"
      }
    }.to_json

    headers = valid_headers(@valid_timestamp, shortcut_payload)

    # Mock the Slack service to return an error
    mock_service = mock
    mock_result = ThreadAgent::Result.failure("No active workspace found for team")
    mock_service.expects(:handle_shortcut).with(instance_of(Hash)).returns(mock_result)

    ThreadAgent::Slack::Service.expects(:new).returns(mock_service)

    post thread_agent_webhooks_slack_path,
         params: shortcut_payload,
         headers: headers

    assert_response :unprocessable_entity
    response_data = JSON.parse(response.body)
    assert_equal "No active workspace found for team", response_data["error"]

    ENV.delete("SLACK_SIGNING_SECRET")
  end

  test "slack webhook handles view submission events successfully" do
    ENV["SLACK_SIGNING_SECRET"] = @signing_secret

    view_submission_payload = {
      type: "view_submission",
      user: {
        id: "U123456",
        name: "testuser"
      },
      view: {
        id: "V123456",
        state: {
          values: {
            workspace_select: {
              selected_workspace: {
                selected_option: {
                  value: "workspace_123"
                }
              }
            },
            template_select: {
              selected_template: {
                selected_option: {
                  value: "template_456"
                }
              }
            }
          }
        }
      }
    }.to_json

    headers = valid_headers(@valid_timestamp, view_submission_payload)

    # Mock the Slack service to return success
    mock_service = mock
    mock_result = ThreadAgent::Result.success("Modal submission processed successfully")
    mock_service.expects(:handle_modal_submission).with(instance_of(Hash)).returns(mock_result)

    ThreadAgent::Slack::Service.expects(:new).returns(mock_service)

    # Assert that the job is enqueued
    assert_enqueued_with(job: ThreadAgent::ProcessWorkflowJob) do
      post thread_agent_webhooks_slack_path,
           params: view_submission_payload,
           headers: headers
    end

    assert_response :ok
    assert_equal "{}", response.body

    ENV.delete("SLACK_SIGNING_SECRET")
  end

  test "slack webhook handles view submission with service error" do
    ENV["SLACK_SIGNING_SECRET"] = @signing_secret

    view_submission_payload = {
      type: "view_submission",
      user: {
        id: "U123456"
      },
      view: {
        state: {
          values: {}
        }
      }
    }.to_json

    headers = valid_headers(@valid_timestamp, view_submission_payload)

    # Mock the Slack service to return an error
    mock_service = mock
    mock_result = ThreadAgent::Result.failure("Missing modal submission data")
    mock_service.expects(:handle_modal_submission).with(instance_of(Hash)).returns(mock_result)

    ThreadAgent::Slack::Service.expects(:new).returns(mock_service)

    # Assert that no job is enqueued when service fails
    assert_no_enqueued_jobs(only: ThreadAgent::ProcessWorkflowJob) do
      post thread_agent_webhooks_slack_path,
           params: view_submission_payload,
           headers: headers
    end

    assert_response :unprocessable_entity
    response_data = JSON.parse(response.body)
    assert_equal "Missing modal submission data", response_data["error"]

    ENV.delete("SLACK_SIGNING_SECRET")
  end
end
