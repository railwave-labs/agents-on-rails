# frozen_string_literal: true

require "test_helper"
require "ostruct"

class ThreadAgent::ProcessWorkflowJobTest < ActiveJob::TestCase
  setup do
    @template = create(:template)
    @notion_database = @template.notion_database

    @valid_thread_data = {
      parent_message: {
        text: "This is the main question about our product roadmap",
        user: "john.doe",
        ts: "1234567890.123456"
      },
      replies: [
        {
          text: "I think we should focus on mobile first",
          user: "jane.smith",
          ts: "1234567891.123456"
        },
        {
          text: "Agreed, mobile is where our users are",
          user: "bob.wilson",
          ts: "1234567892.123456"
        }
      ],
      channel_id: "C1234567890",
      thread_ts: "1234567890.123456"
    }

    # Mock successful OpenAI service response
    mock_openai_response = OpenStruct.new(
      success?: true,
      data: "# Summary\n\nThe team discussed mobile-first approach for the product roadmap.\n\n## Key Points\n\n• Focus on mobile development\n• Users are primarily mobile\n• Roadmap should prioritize mobile features",
      model: "gpt-4"
    )

    ThreadAgent::Openai::Service.any_instance.stubs(:transform_content).returns(mock_openai_response)

    # Mock successful Notion service response for create_page_from_workflow
    mock_notion_response = ThreadAgent::Result.success({
      id: "notion-page-123",
      url: "https://notion.so/page-123",
      title: "This is the main question about our product roadmap",
      created_time: "2024-01-01T12:00:00.000Z"
    })

    ThreadAgent::Notion::Service.any_instance.stubs(:create_page_from_workflow).returns(mock_notion_response)

    # Mock Slack service for thread processing
    mock_slack_response = ThreadAgent::Result.success(@valid_thread_data)
    ThreadAgent::Slack::Service.any_instance.stubs(:process_workflow_input).returns(mock_slack_response)

    # Mock service initializations to prevent API credential checks
    mock_slack_service = stub(process_workflow_input: mock_slack_response)
    mock_openai_service = stub(
      transform_content: mock_openai_response,
      model: "gpt-4"
    )
    mock_notion_service = stub(create_page_from_workflow: mock_notion_response)

    ThreadAgent::Slack::Service.stubs(:new).returns(mock_slack_service)
    ThreadAgent::Openai::Service.stubs(:new).returns(mock_openai_service)
    ThreadAgent::Notion::Service.stubs(:new).returns(mock_notion_service)
  end

  test "successfully processes workflow with all steps" do
    workflow_run = create(:workflow_run,
      template: @template,
      input_data: { thread_data: @valid_thread_data }.to_json
    )

    assert_enqueued_with(job: ThreadAgent::ProcessWorkflowJob, args: [ workflow_run.id ]) do
      ThreadAgent::ProcessWorkflowJob.perform_later(workflow_run.id)
    end

    perform_enqueued_jobs

    workflow_run.reload
    assert_equal "completed", workflow_run.status
    assert_not_nil workflow_run.output_data
    assert_includes workflow_run.output_data.keys, "notion_page_url"
  end

  test "processes workflow with Slack fetching when only channel and thread info provided" do
    workflow_run = create(:workflow_run,
      template: @template,
      input_data: {
        channel_id: "C1234567890",
        thread_ts: "1234567890.123456"
      }.to_json
    )

    perform_enqueued_jobs do
      ThreadAgent::ProcessWorkflowJob.perform_later(workflow_run.id)
    end

    workflow_run.reload
    assert_equal "completed", workflow_run.status
    assert_not_nil workflow_run.output_data
  end

  test "processes hash input_data correctly" do
    workflow_run = create(:workflow_run,
      template: @template,
      input_data: { thread_data: @valid_thread_data }
    )

    perform_enqueued_jobs do
      ThreadAgent::ProcessWorkflowJob.perform_later(workflow_run.id)
    end

    workflow_run.reload
    assert_equal "completed", workflow_run.status
    assert_not_nil workflow_run.output_data
  end

  test "handles missing input_data" do
    # Create workflow_run with slack fields to pass validation, then mock Slack service failure
    workflow_run = create(:workflow_run, :with_slack_info,
      template: @template,
      input_data: nil,
      slack_thread_ts: "1234567890.123456" # Add missing field from trait
    )

    # Mock Slack service failure for missing data using explicit mock
    mock_service = mock("slack_service")
    mock_service.expects(:process_workflow_input).returns(
      ThreadAgent::Result.failure("Missing channel_id or thread_ts in workflow input")
    )

    ThreadAgent::Slack::Service.expects(:new).returns(mock_service)

    perform_enqueued_jobs do
      ThreadAgent::ProcessWorkflowJob.perform_later(workflow_run.id)
    end

    workflow_run.reload
    assert_equal "failed", workflow_run.status
    assert_match(/Missing channel_id or thread_ts/, workflow_run.error_message)
  end

  test "handles invalid JSON in input_data" do
    # Test that invalid JSON is caught by validation and handled gracefully
    workflow_run = create(:workflow_run,
      template: @template,
      input_data: "invalid json{"
    )

    perform_enqueued_jobs do
      ThreadAgent::ProcessWorkflowJob.perform_later(workflow_run.id)
    end

    workflow_run.reload
    assert_equal "failed", workflow_run.status
    assert_match(/Invalid input data format/, workflow_run.error_message)
  end

  test "handles Slack service errors" do
    # Mock Slack service failure using explicit mock
    mock_service = mock("slack_service")
    mock_service.expects(:process_workflow_input).returns(
      ThreadAgent::Result.failure("Slack API error")
    )

    ThreadAgent::Slack::Service.expects(:new).returns(mock_service)

    workflow_run = create(:workflow_run,
      template: @template,
      input_data: {
        channel_id: "C1234567890",
        thread_ts: "1234567890.123456"
      }.to_json
    )

    perform_enqueued_jobs do
      ThreadAgent::ProcessWorkflowJob.perform_later(workflow_run.id)
    end

    workflow_run.reload
    assert_equal "failed", workflow_run.status
    assert_match(/Slack API error/, workflow_run.error_message)
  end

  test "handles OpenAI service errors" do
    # Mock services with proper call sequence
    mock_slack_service = mock("slack_service")
    mock_slack_service.expects(:process_workflow_input).returns(
      ThreadAgent::Result.success(@valid_thread_data)
    )

    mock_openai_service = mock("openai_service")
    mock_openai_service.expects(:transform_content)
      .raises(ThreadAgent::OpenaiError, "API rate limit exceeded")

    ThreadAgent::Slack::Service.expects(:new).returns(mock_slack_service)
    ThreadAgent::Openai::Service.expects(:new).returns(mock_openai_service)

    workflow_run = create(:workflow_run,
      template: @template,
      input_data: { thread_data: @valid_thread_data }.to_json
    )

    perform_enqueued_jobs do
      ThreadAgent::ProcessWorkflowJob.perform_later(workflow_run.id)
    end

    workflow_run.reload
    assert_equal "failed", workflow_run.status
    assert_match(/API rate limit exceeded/, workflow_run.error_message)
  end

  test "handles OpenAI service returning failure result" do
    # Mock services with proper call sequence
    mock_slack_service = mock("slack_service")
    mock_slack_service.expects(:process_workflow_input).returns(
      ThreadAgent::Result.success(@valid_thread_data)
    )

    failure_result = OpenStruct.new(
      success?: false,
      error: "Model is temporarily unavailable"
    )
    mock_openai_service = mock("openai_service")
    mock_openai_service.expects(:transform_content).returns(failure_result)

    ThreadAgent::Slack::Service.expects(:new).returns(mock_slack_service)
    ThreadAgent::Openai::Service.expects(:new).returns(mock_openai_service)

    workflow_run = create(:workflow_run,
      template: @template,
      input_data: { thread_data: @valid_thread_data }.to_json
    )

    perform_enqueued_jobs do
      ThreadAgent::ProcessWorkflowJob.perform_later(workflow_run.id)
    end

    workflow_run.reload
    assert_equal "failed", workflow_run.status
    assert_match(/OpenAI service returned error/, workflow_run.error_message)
  end

  test "handles missing Notion database configuration" do
    # Mock services with proper call sequence
    mock_slack_service = mock("slack_service")
    mock_slack_service.expects(:process_workflow_input).returns(
      ThreadAgent::Result.success(@valid_thread_data)
    )

    mock_openai_service = mock("openai_service")
    mock_openai_service.expects(:transform_content).returns(
      ThreadAgent::Result.success("AI generated content")
    )
    mock_openai_service.expects(:model).returns("gpt-4")

    # Mock the Notion service to return a failure for missing database configuration
    mock_notion_service = mock("notion_service")
    mock_notion_service.expects(:create_page_from_workflow).returns(
      ThreadAgent::Result.failure("No Notion database configured for template")
    )

    ThreadAgent::Slack::Service.expects(:new).returns(mock_slack_service)
    ThreadAgent::Openai::Service.expects(:new).returns(mock_openai_service)
    ThreadAgent::Notion::Service.expects(:new).returns(mock_notion_service)

    # Use the existing template with a notion_database (to satisfy NOT NULL constraint)
    # but mock the Notion service to simulate a configuration error
    workflow_run = create(:workflow_run,
      template: @template,
      input_data: { thread_data: @valid_thread_data }.to_json
    )

    perform_enqueued_jobs do
      ThreadAgent::ProcessWorkflowJob.perform_later(workflow_run.id)
    end

    workflow_run.reload
    # When Notion service fails, workflow should fail
    assert_equal "failed", workflow_run.status
    assert_match(/No Notion database configured/, workflow_run.error_message)
  end

  test "handles Notion service errors" do
    # Mock services with proper call sequence
    mock_slack_service = mock("slack_service")
    mock_slack_service.expects(:process_workflow_input).returns(
      ThreadAgent::Result.success(@valid_thread_data)
    )

    mock_openai_service = mock("openai_service")
    mock_openai_service.expects(:transform_content).returns(
      ThreadAgent::Result.success("AI generated content")
    )
    mock_openai_service.expects(:model).returns("gpt-4")

    mock_notion_service = mock("notion_service")
    mock_notion_service.expects(:create_page_from_workflow).returns(
      ThreadAgent::Result.failure("Notion API error")
    )

    ThreadAgent::Slack::Service.expects(:new).returns(mock_slack_service)
    ThreadAgent::Openai::Service.expects(:new).returns(mock_openai_service)
    ThreadAgent::Notion::Service.expects(:new).returns(mock_notion_service)

    workflow_run = create(:workflow_run,
      template: @template,
      input_data: { thread_data: @valid_thread_data }.to_json
    )

    perform_enqueued_jobs do
      ThreadAgent::ProcessWorkflowJob.perform_later(workflow_run.id)
    end

    workflow_run.reload
    assert_equal "failed", workflow_run.status
    assert_match(/Notion API error/, workflow_run.error_message)
  end

  test "creates rich Notion page content with proper structure" do
    workflow_run = create(:workflow_run,
      template: @template,
      input_data: { thread_data: @valid_thread_data }.to_json
    )

    perform_enqueued_jobs do
      ThreadAgent::ProcessWorkflowJob.perform_later(workflow_run.id)
    end

    workflow_run.reload
    assert_equal "completed", workflow_run.status
    # The actual content structure is now tested in the service layer tests
    assert_not_nil workflow_run.output_data["notion_page_url"]
  end

  test "builds comprehensive page properties" do
    workflow_run = create(:workflow_run,
      template: @template,
      input_data: { thread_data: @valid_thread_data }.to_json
    )

    perform_enqueued_jobs do
      ThreadAgent::ProcessWorkflowJob.perform_later(workflow_run.id)
    end

    workflow_run.reload
    assert_equal "completed", workflow_run.status
    # The actual property building is now tested in the PageBuilder tests
    assert_not_nil workflow_run.output_data["notion_page_url"]
  end
end
