# frozen_string_literal: true

require "test_helper"

module ThreadAgent
  class OpenaiWorkflowTest < ActionDispatch::IntegrationTest
    def setup
      # Set up environment variables for testing
      ENV["THREAD_AGENT_OPENAI_API_KEY"] = "test-openai-key"
      ENV["THREAD_AGENT_OPENAI_MODEL"] = "gpt-4"
      ENV["THREAD_AGENT_SLACK_BOT_TOKEN"] = "xoxb-test-slack-token"
      ENV["THREAD_AGENT_SLACK_SIGNING_SECRET"] = "test-signing-secret"
      ENV["THREAD_AGENT_NOTION_TOKEN"] = "test-notion-token"

      # Reset ThreadAgent configuration
      ThreadAgent.reset_configuration!

      # Create test data
      @workspace = create(:notion_workspace, slack_team_id: "T123456")
      @database = create(:notion_database, notion_workspace: @workspace)
      @template = create(:template,
        notion_database: @database,
        name: "Meeting Notes Template",
        content: "Transform this Slack thread into structured meeting notes for Notion with clear headings and action items."
      )

      # Set up job testing
      ActiveJob::Base.queue_adapter = :test
      clear_enqueued_jobs

      # Create realistic thread data fixture
      @thread_data = {
        parent_message: {
          user: "U123456",
          text: "Let's discuss the Q1 planning priorities",
          ts: "1640995200.000100",
          channel: "C123456"
        },
        replies: [
          {
            user: "U789012",
            text: "I think we should focus on the new user onboarding flow",
            ts: "1640995260.000200"
          },
          {
            user: "U345678",
            text: "Agreed! We also need to improve our analytics dashboard",
            ts: "1640995320.000300"
          }
        ],
        channel_id: "C123456",
        thread_ts: "1640995200.000100"
      }

      # Use a simple, generic OpenAI response for testing workflow integration
      # Content quality testing should be done manually
      @generic_openai_response = {
        "choices" => [
          {
            "message" => {
              "content" => "# Meeting Summary\n\nProcessed thread content with structured format."
            }
          }
        ]
      }.to_json

      # Set up WebMock for external API calls
      WebMock.reset!

      # Set up generic Notion API stub for successful workflow completion
      # This stub will handle all Notion page creation requests
      @notion_page_response = {
        "id" => "page_123456",
        "url" => "https://notion.so/page_123456",
        "created_time" => "2025-06-26T11:10:41.000Z",
        "properties" => {}
      }.to_json

      stub_request(:post, "https://api.notion.com/v1/pages")
        .with(
          headers: {
            "Accept" => "application/json; charset=utf-8",
            "Authorization" => "Bearer test-notion-token",
            "Content-Type" => "application/json",
            "Notion-Version" => "2022-02-22"
          }
        )
        .to_return(
          status: 200,
          body: @notion_page_response,
          headers: { "Content-Type" => "application/json" }
        )
    end

    def teardown
      # Clean up environment variables
      ENV.delete("THREAD_AGENT_OPENAI_API_KEY")
      ENV.delete("THREAD_AGENT_OPENAI_MODEL")
      ENV.delete("THREAD_AGENT_SLACK_BOT_TOKEN")
      ENV.delete("THREAD_AGENT_SLACK_SIGNING_SECRET")
      ENV.delete("THREAD_AGENT_NOTION_TOKEN")

      # Reset WebMock
      WebMock.reset!

      # Reset jobs
      clear_enqueued_jobs
    end

    test "successfully orchestrates OpenAI service integration within job context" do
      # Test focuses on workflow orchestration, not content quality
      openai_stub = stub_request(:post, "https://api.openai.com/v1/chat/completions")
        .with(
          headers: {
            "Authorization" => "Bearer test-openai-key",
            "Content-Type" => "application/json"
          }
        )
        .to_return(
          status: 200,
          body: @generic_openai_response,
          headers: { "Content-Type" => "application/json" }
        )

      workflow_run = create(:workflow_run,
        template: @template,
        slack_channel_id: @thread_data[:channel_id],
        slack_message_id: @thread_data[:thread_ts],
        slack_thread_ts: @thread_data[:thread_ts],
        status: "running",
        input_data: { thread_data: @thread_data }.to_json
      )

      # Execute the job - this tests the integration pipeline
      result = nil
      assert_nothing_raised do
        result = ProcessWorkflowJob.perform_now(workflow_run.id)
      end

      # Verify job completed successfully
      assert result, "Job should return truthy value on success"

      # Verify OpenAI API was called exactly once with correct structure
      assert_requested :post, "https://api.openai.com/v1/chat/completions", times: 1

      # Test the request structure - this is what we can reliably verify
      assert_requested :post, "https://api.openai.com/v1/chat/completions" do |req|
        body = JSON.parse(req.body)

        # Verify essential request parameters
        assert_equal "gpt-4", body["model"]
        assert_equal 1000, body["max_tokens"]
        assert_equal 0.7, body["temperature"]
        assert body["messages"].is_a?(Array)
        assert body["messages"].length >= 2 # system + user messages

        # Verify message structure without checking specific content
        messages = body["messages"]

        system_message = messages.find { |m| m["role"] == "system" }
        assert system_message, "Should include system message"
        assert system_message["content"].is_a?(String)
        assert system_message["content"].length > 0

        user_message = messages.find { |m| m["role"] == "user" }
        assert user_message, "Should include user message with thread data"
        assert user_message["content"].is_a?(String)
        assert user_message["content"].length > 0

        true
      end
    end

    test "properly handles OpenAI service retry behavior" do
      # Test retry logic - this is important for reliability
      retry_count = 0
      openai_stub = stub_request(:post, "https://api.openai.com/v1/chat/completions")
        .to_return do |request|
          retry_count += 1
          if retry_count <= 2
            { status: 500, body: "Internal Server Error" }
          else
            {
              status: 200,
              body: @generic_openai_response,
              headers: { "Content-Type" => "application/json" }
            }
          end
        end

      workflow_run = create(:workflow_run,
        template: @template,
        input_data: { thread_data: @thread_data }.to_json
      )

      # Job should succeed after retries
      assert_nothing_raised do
        ProcessWorkflowJob.perform_now(workflow_run.id)
      end

      # Verify retry behavior worked correctly
      assert_equal 3, retry_count, "Should have retried twice before succeeding"
      assert_requested :post, "https://api.openai.com/v1/chat/completions", times: 3
    end

    test "raises appropriate errors when OpenAI service fails persistently" do
      # Test error handling - important for debugging production issues
      stub_request(:post, "https://api.openai.com/v1/chat/completions")
        .to_return(status: 500, body: "Internal Server Error")

      workflow_run = create(:workflow_run,
        template: @template,
        input_data: { thread_data: @thread_data }.to_json
      )

      # Job should raise ThreadAgent::OpenaiError after retries exhausted
      # ActiveJob's retry_on will eventually re-raise the error after all attempts
      assert_raises(ThreadAgent::OpenaiError) do
        # Disable retry_on for this test by performing the job directly
        job = ProcessWorkflowJob.new
        job.perform(workflow_run.id)
      end
    end

    test "validates thread_data structure before making OpenAI requests" do
      # Test input validation - prevents bad requests
      workflow_run = create(:workflow_run, template: @template)

      # Test with various invalid thread_data structures
      invalid_workflow_runs = [
        create(:workflow_run, template: @template, input_data: nil),
        create(:workflow_run, template: @template, input_data: {}.to_json),
        create(:workflow_run, template: @template, input_data: { replies: [] }.to_json) # missing parent_message
      ]

      invalid_workflow_runs.each do |invalid_run|
        assert_raises(ThreadAgent::OpenaiError) do
          # Disable retry_on for this test by performing the job directly
          job = ProcessWorkflowJob.new
          job.perform(invalid_run.id)
        end
      end

      # Verify no OpenAI requests were made for invalid data
      assert_not_requested :post, "https://api.openai.com/v1/chat/completions"
    end

    test "handles different template configurations correctly" do
      # Test template flexibility
      openai_stub = stub_request(:post, "https://api.openai.com/v1/chat/completions")
        .to_return(
          status: 200,
          body: @generic_openai_response,
          headers: { "Content-Type" => "application/json" }
        )

      # Test with custom template
      custom_template = create(:template,
        notion_database: @database,
        name: "Custom Template",
        content: "Custom system prompt for processing threads."
      )

      workflow_run = create(:workflow_run,
        template: custom_template,
        input_data: { thread_data: @thread_data }.to_json
      )

      assert_nothing_raised do
        ProcessWorkflowJob.perform_now(workflow_run.id)
      end

      # Verify template content was used in system message
      assert_requested :post, "https://api.openai.com/v1/chat/completions" do |req|
        body = JSON.parse(req.body)
        system_message = body["messages"].find { |m| m["role"] == "system" }
        assert_includes system_message["content"], custom_template.content
        true
      end
    end

    test "processes workflow without template using default system prompt" do
      # Test template flexibility - workflow can work without a template
      openai_stub = stub_request(:post, "https://api.openai.com/v1/chat/completions")
        .to_return(
          status: 200,
          body: @generic_openai_response,
          headers: { "Content-Type" => "application/json" }
        )

      workflow_run = create(:workflow_run,
        template: nil, # No template provided
        input_data: { thread_data: @thread_data }.to_json
      )

      assert_nothing_raised do
        ProcessWorkflowJob.perform_now(workflow_run.id)
      end

      # Verify OpenAI was called with default system prompt
      assert_requested :post, "https://api.openai.com/v1/chat/completions" do |req|
        body = JSON.parse(req.body)
        system_message = body["messages"].find { |m| m["role"] == "system" }

        # Should use default prompt when no template provided
        assert system_message, "Should include default system message"
        assert system_message["content"].is_a?(String)
        assert system_message["content"].length > 0

        true
      end
    end

    test "includes proper instrumentation during workflow processing" do
      # Test observability features
      stub_request(:post, "https://api.openai.com/v1/chat/completions")
        .to_return(
          status: 200,
          body: @generic_openai_response,
          headers: { "Content-Type" => "application/json" }
        )

      workflow_run = create(:workflow_run,
        template: @template,
        input_data: { thread_data: @thread_data }.to_json
      )

      # Capture instrumentation events
      events = []
      ActiveSupport::Notifications.subscribe("thread_agent.workflow.process") do |name, start, finish, id, payload|
        events << { name: name, payload: payload }
      end

      ProcessWorkflowJob.perform_now(workflow_run.id)

      # Verify instrumentation was triggered
      assert_equal 1, events.size
      assert_equal "thread_agent.workflow.process", events.first[:name]
      assert events.first[:payload].include?(:workflow_run_id)
    end

    test "processes complex thread structures correctly" do
      # Test handling of various Slack message features
      complex_thread_data = {
        parent_message: {
          user: "U123456",
          text: "Team standup - what's everyone working on? <@U789012> <@U345678>",
          ts: "1640995200.000100",
          channel: "C123456"
        },
        replies: [
          {
            user: "U789012",
            text: "Working on the API integration :rocket:",
            ts: "1640995260.000200"
          },
          {
            user: "U345678",
            text: "Here's a link: https://figma.com/design123",
            ts: "1640995320.000300"
          }
        ],
        channel_id: "C123456",
        thread_ts: "1640995200.000100"
      }

      openai_stub = stub_request(:post, "https://api.openai.com/v1/chat/completions")
        .to_return(
          status: 200,
          body: @generic_openai_response,
          headers: { "Content-Type" => "application/json" }
        )

      workflow_run = create(:workflow_run,
        template: @template,
        input_data: { thread_data: complex_thread_data }.to_json
      )

      assert_nothing_raised do
        ProcessWorkflowJob.perform_now(workflow_run.id)
      end

      # Verify complex thread data was included in the request
      assert_requested :post, "https://api.openai.com/v1/chat/completions" do |req|
        body = JSON.parse(req.body)
        user_message = body["messages"].find { |m| m["role"] == "user" }

        # Verify thread structure is preserved in some form
        assert user_message["content"].length > 0
        assert_includes user_message["content"].downcase, "standup"

        true
      end
    end
  end
end
