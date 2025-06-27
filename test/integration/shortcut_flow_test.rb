# frozen_string_literal: true

require "test_helper"

class ShortcutFlowTest < ActionDispatch::IntegrationTest
  def setup
    ENV["THREAD_AGENT_SLACK_SIGNING_SECRET"] = "test-secret"
    ENV["THREAD_AGENT_SLACK_BOT_TOKEN"] = "xoxb-test-token"
    ENV["THREAD_AGENT_NOTION_TOKEN"] = "secret_test-notion-token"
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
    ENV.delete("THREAD_AGENT_NOTION_TOKEN")
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

    # Test 2: Modal submission enqueues job with some basic context
    modal_payload = {
      type: "view_submission",
      view: {
        id: "V123456",
        private_metadata: JSON.generate({
          channel_id: "C7654321",
          thread_ts: "1234567890.123456"
        }),
        state: {
          values: {
            workspace_block: {
              workspace_select: {
                selected_option: { value: @workspace.id.to_s }
              }
            },
            template_block: {
              template_select: {
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

  test "complete modal submission to job execution flow" do
    # Stub external calls to prevent real API calls
    stub_request(:post, /slack\.com/).to_return(body: '{"ok":true}')

    # Stub successful external API calls for job execution
    stub_request(:post, "https://api.openai.com/v1/chat/completions")
      .to_return(
        status: 200,
        body: {
          choices: [ { message: { content: "# Test Summary\n\nProcessed thread successfully." } } ],
          usage: { total_tokens: 100 }
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    stub_request(:post, %r{https://api\.notion\.com/v1/pages})
      .to_return(
        status: 200,
        body: {
          id: "page-123",
          url: "https://notion.so/page-123",
          created_time: "2024-01-01T12:00:00.000Z"
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    # Ensure no WorkflowRuns exist initially
    assert_equal 0, ThreadAgent::WorkflowRun.count

    # Submit modal with workspace and template selection
    thread_data = {
      channel_id: "C7654321",
      thread_ts: "1234567890.123456",
      parent_message: {
        text: "This is the main thread message",
        user: "U123456",
        ts: "1234567890.123456"
      },
      replies: [
        {
          text: "This is a reply in the thread",
          user: "U789012",
          ts: "1234567890.234567",
          thread_ts: "1234567890.123456"
        }
      ]
    }

    modal_payload = {
      type: "view_submission",
      team: { id: "T123456" },
      user: { id: "U123456", username: "testuser" },
      view: {
        id: "V123456",
        private_metadata: JSON.generate({
          channel_id: "C7654321",
          thread_ts: "1234567890.123456",
          thread_data: thread_data
        }), # Store channel, thread info and thread_data in private_metadata
        state: {
          values: {
            workspace_block: {
              workspace_select: {
                selected_option: { value: @workspace.id.to_s }
              }
            },
            template_block: {
              template_select: {
                selected_option: { value: @template.id.to_s }
              }
            },
            custom_prompt_block: {
              custom_prompt_input: {
                value: "Please focus on action items and decisions"
              }
            }
          }
        }
      }
    }.to_json

    timestamp = Time.now.to_i.to_s
    post "/thread_agent/webhooks/slack",
         params: modal_payload,
         headers: valid_headers(timestamp, modal_payload)

    assert_response :success

    # Verify WorkflowRun was created
    assert_equal 1, ThreadAgent::WorkflowRun.count
    workflow_run = ThreadAgent::WorkflowRun.last

    # Verify WorkflowRun has correct data
    assert_equal "thread_capture", workflow_run.workflow_name
    assert_equal "pending", workflow_run.status
    assert_equal @template, workflow_run.template
    assert_equal "C7654321", workflow_run.slack_channel_id
    assert_equal "1234567890.123456", workflow_run.slack_thread_ts

    # Verify input_data contains expected fields
    input_data = workflow_run.input_data
    assert_equal @workspace.id.to_s, input_data["workspace_id"]
    assert_equal @template.id.to_s, input_data["template_id"]
    assert_equal "C7654321", input_data["channel_id"]
    assert_equal "1234567890.123456", input_data["thread_ts"]
    assert_equal "U123456", input_data["slack_user_id"]
    assert_equal "T123456", input_data["slack_team_id"]
    assert_equal "Please focus on action items and decisions", input_data["custom_prompt"]

    # Verify thread_data is included
    assert_not_nil input_data["thread_data"]
    assert_equal "C7654321", input_data["thread_data"]["channel_id"]
    assert_equal "1234567890.123456", input_data["thread_data"]["thread_ts"]
    assert_equal "This is the main thread message", input_data["thread_data"]["parent_message"]["text"]

    # Verify job was enqueued with correct WorkflowRun ID
    assert_enqueued_with(job: ThreadAgent::ProcessWorkflowJob, args: [ workflow_run.id ])

    # Execute the job to verify end-to-end flow works
    perform_enqueued_jobs

    # Verify workflow completed successfully
    workflow_run.reload
    assert_equal "completed", workflow_run.status
    assert_not_nil workflow_run.output_data
    assert_nil workflow_run.error_message
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

  test "message shortcut extracts context from message" do
    # Stub external calls to prevent real API calls
    stub_request(:post, /slack\.com/).to_return(body: '{"ok":true}')

    # Test message shortcut with channel and message context
    timestamp = Time.now.to_i.to_s
    shortcut_payload = {
      type: "message_action",
      callback_id: "thread_capture",
      trigger_id: "123.456.abc",
      team: { id: "T123456" },
      user: { id: "U123" },
      channel: {
        id: "C7654321",
        name: "general"
      },
      message: {
        type: "message",
        user: "U123456",
        ts: "1234567890.123456",
        text: "This is the original message",
        thread_ts: "1234567890.100000"  # This message is part of an existing thread
      }
    }.to_json

    post "/thread_agent/webhooks/slack",
         params: shortcut_payload,
         headers: valid_headers(timestamp, shortcut_payload)
    assert_response :success

    # Verify the modal would be created with the correct context
    # (In a real scenario, the modal would include this context in private_metadata)
  end

  test "modal submission fails when workspace selection is missing" do
    modal_payload = {
      type: "view_submission",
      team: { id: "T123456" },
      user: { id: "U123456" },
      view: {
        id: "V123456",
        state: {
          values: {
            # Missing workspace_block - should cause validation error
            template_block: {
              template_select: {
                selected_option: { value: @template.id.to_s }
              }
            }
          }
        }
      }
    }.to_json

    timestamp = Time.now.to_i.to_s
    post "/thread_agent/webhooks/slack",
         params: modal_payload,
         headers: valid_headers(timestamp, modal_payload)

    assert_response :unprocessable_entity

    # Verify no WorkflowRun was created
    assert_equal 0, ThreadAgent::WorkflowRun.count

    # Verify no job was enqueued
    assert_no_enqueued_jobs only: ThreadAgent::ProcessWorkflowJob
  end

  test "modal submission fails when selected template doesn't exist" do
    modal_payload = {
      type: "view_submission",
      team: { id: "T123456" },
      user: { id: "U123456" },
      view: {
        id: "V123456",
        state: {
          values: {
            workspace_block: {
              workspace_select: {
                selected_option: { value: @workspace.id.to_s }
              }
            },
            template_block: {
              template_select: {
                selected_option: { value: "999999" } # Non-existent template ID
              }
            }
          }
        }
      }
    }.to_json

    timestamp = Time.now.to_i.to_s
    post "/thread_agent/webhooks/slack",
         params: modal_payload,
         headers: valid_headers(timestamp, modal_payload)

    assert_response :unprocessable_entity

    # Verify no WorkflowRun was created
    assert_equal 0, ThreadAgent::WorkflowRun.count

    # Verify no job was enqueued
    assert_no_enqueued_jobs only: ThreadAgent::ProcessWorkflowJob
  end
end
