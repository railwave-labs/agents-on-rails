# frozen_string_literal: true

require "test_helper"

class ThreadAgent::WorkflowRunTest < ActiveSupport::TestCase
  def setup
    @valid_attributes = {
      workflow_name: "test_workflow",
      status: "pending"
    }
  end

  test "should create workflow run with valid attributes" do
    workflow_run = ThreadAgent::WorkflowRun.new(@valid_attributes)
    assert workflow_run.valid?
    assert workflow_run.save
  end

  test "should require workflow_name" do
    workflow_run = ThreadAgent::WorkflowRun.new(@valid_attributes.except(:workflow_name))
    assert_not workflow_run.valid?
    assert_includes workflow_run.errors[:workflow_name], "can't be blank"
  end

  test "should require status" do
    workflow_run = ThreadAgent::WorkflowRun.new(@valid_attributes.except(:status))
    workflow_run.status = nil
    assert_not workflow_run.valid?
    assert_includes workflow_run.errors[:status], "can't be blank"
  end

  test "should validate status inclusion" do
    assert_raises(ArgumentError) do
      ThreadAgent::WorkflowRun.new(@valid_attributes.merge(status: "invalid_status"))
    end
  end

  test "should validate workflow_name length" do
    # Test minimum length
    workflow_run = ThreadAgent::WorkflowRun.new(@valid_attributes.merge(workflow_name: ""))
    assert_not workflow_run.valid?
    assert_includes workflow_run.errors[:workflow_name], "is too short (minimum is 1 character)"

    # Test maximum length
    long_name = "a" * 256
    workflow_run = ThreadAgent::WorkflowRun.new(@valid_attributes.merge(workflow_name: long_name))
    assert_not workflow_run.valid?
    assert_includes workflow_run.errors[:workflow_name], "is too long (maximum is 255 characters)"
  end

  test "should validate error_message length" do
    long_error = "a" * 2001
    workflow_run = ThreadAgent::WorkflowRun.new(@valid_attributes.merge(error_message: long_error))
    assert_not workflow_run.valid?
    assert_includes workflow_run.errors[:error_message], "is too long (maximum is 2000 characters)"
  end

    test "should require error_message when status is failed" do
    workflow_run = ThreadAgent::WorkflowRun.create!(@valid_attributes)
    workflow_run.status = "failed"
    workflow_run.error_message = nil

    assert_not workflow_run.valid?
    assert_includes workflow_run.errors[:error_message], "can't be blank"
  end

  test "should allow error_message to be nil when status is not failed" do
    workflow_run = ThreadAgent::WorkflowRun.new(@valid_attributes.merge(error_message: nil))
    assert workflow_run.valid?
  end

    test "should validate finished_at is after started_at" do
    workflow_run = ThreadAgent::WorkflowRun.create!(@valid_attributes)
    workflow_run.started_at = 1.hour.ago
    workflow_run.finished_at = 2.hours.ago

    assert_not workflow_run.valid?
    assert_includes workflow_run.errors[:finished_at], "must be greater than #{workflow_run.started_at}"
  end

  test "should have correct enums" do
    expected_statuses = %w[pending running completed failed cancelled]
    assert_equal expected_statuses, ThreadAgent::WorkflowRun.statuses.keys
  end

  test "should have correct scopes" do
    # Create test data
    pending_run = ThreadAgent::WorkflowRun.create!(@valid_attributes.merge(status: "pending"))
    running_run = ThreadAgent::WorkflowRun.create!(@valid_attributes.merge(status: "running"))
    completed_run = ThreadAgent::WorkflowRun.create!(@valid_attributes.merge(status: "completed"))
    failed_run = ThreadAgent::WorkflowRun.create!(@valid_attributes.merge(status: "failed", error_message: "Test error"))
    other_workflow_run = ThreadAgent::WorkflowRun.create!(@valid_attributes.merge(workflow_name: "other_workflow"))

    # Test scopes
    assert_includes ThreadAgent::WorkflowRun.active, pending_run
    assert_includes ThreadAgent::WorkflowRun.active, running_run
    assert_not_includes ThreadAgent::WorkflowRun.active, completed_run

    assert_includes ThreadAgent::WorkflowRun.completed_successfully, completed_run
    assert_not_includes ThreadAgent::WorkflowRun.completed_successfully, failed_run

    assert_includes ThreadAgent::WorkflowRun.failed_runs, failed_run
    assert_not_includes ThreadAgent::WorkflowRun.failed_runs, completed_run

    assert_includes ThreadAgent::WorkflowRun.by_workflow("test_workflow"), pending_run
    assert_not_includes ThreadAgent::WorkflowRun.by_workflow("test_workflow"), other_workflow_run
  end

  test "duration should calculate correctly" do
    workflow_run = ThreadAgent::WorkflowRun.create!(@valid_attributes)

    # No duration without timestamps
    assert_nil workflow_run.duration

    # Set timestamps
    workflow_run.update!(started_at: 1.hour.ago, finished_at: Time.current)
    assert_in_delta 3600, workflow_run.duration, 5 # Within 5 seconds
  end

  test "active? should work correctly" do
    pending_run = ThreadAgent::WorkflowRun.create!(@valid_attributes.merge(status: "pending"))
    running_run = ThreadAgent::WorkflowRun.create!(@valid_attributes.merge(status: "running"))
    completed_run = ThreadAgent::WorkflowRun.create!(@valid_attributes.merge(status: "completed"))

    assert pending_run.active?
    assert running_run.active?
    assert_not completed_run.active?
  end

  test "finished? should work correctly" do
    pending_run = ThreadAgent::WorkflowRun.create!(@valid_attributes.merge(status: "pending"))
    completed_run = ThreadAgent::WorkflowRun.create!(@valid_attributes.merge(status: "completed"))
    failed_run = ThreadAgent::WorkflowRun.create!(@valid_attributes.merge(status: "failed", error_message: "Test error"))
    cancelled_run = ThreadAgent::WorkflowRun.create!(@valid_attributes.merge(status: "cancelled"))

    assert_not pending_run.finished?
    assert completed_run.finished?
    assert failed_run.finished?
    assert cancelled_run.finished?
  end

  test "mark_started! should update status and started_at" do
    workflow_run = ThreadAgent::WorkflowRun.create!(@valid_attributes)
    assert_nil workflow_run.started_at
    assert workflow_run.pending?

    workflow_run.mark_started!
    workflow_run.reload

    assert workflow_run.running?
    assert_not_nil workflow_run.started_at
  end

  test "mark_completed! should update status, finished_at, and output_payload" do
    workflow_run = ThreadAgent::WorkflowRun.create!(@valid_attributes)
    output_data = { result: "success" }

    workflow_run.mark_completed!(output_data)
    workflow_run.reload

    assert workflow_run.completed?
    assert_not_nil workflow_run.finished_at
    assert_equal output_data.stringify_keys, workflow_run.output_payload
  end

  test "mark_failed! should update status, finished_at, and error_message" do
    workflow_run = ThreadAgent::WorkflowRun.create!(@valid_attributes)
    error_msg = "Something went wrong"

    workflow_run.mark_failed!(error_msg)
    workflow_run.reload

    assert workflow_run.failed?
    assert_not_nil workflow_run.finished_at
    assert_equal error_msg, workflow_run.error_message
  end

  test "mark_cancelled! should update status and finished_at" do
    workflow_run = ThreadAgent::WorkflowRun.create!(@valid_attributes)

    workflow_run.mark_cancelled!
    workflow_run.reload

    assert workflow_run.cancelled?
    assert_not_nil workflow_run.finished_at
  end

  test "create_for_workflow class method should work correctly" do
    input_data = { prompt: "test prompt" }
    workflow_run = ThreadAgent::WorkflowRun.create_for_workflow(
      "test_workflow",
      thread_id: "thread_123",
      input_data: input_data,
      external_id: "ext_456"
    )

    assert workflow_run.persisted?
    assert_equal "test_workflow", workflow_run.workflow_name
    assert workflow_run.pending?
    assert_equal "thread_123", workflow_run.thread_id
    assert_equal input_data.stringify_keys, workflow_run.input_payload
    assert_equal "ext_456", workflow_run.external_id
    assert_equal [], workflow_run.steps
  end

  test "should set correct table name" do
    assert_equal "thread_agent_workflow_runs", ThreadAgent::WorkflowRun.table_name
  end

  # Tests for step management functionality
  test "should initialize with empty steps array" do
    workflow_run = ThreadAgent::WorkflowRun.create!(@valid_attributes)
    assert_equal [], workflow_run.steps
  end

  test "add_step should record completed step" do
    workflow_run = ThreadAgent::WorkflowRun.create!(@valid_attributes)

    workflow_run.add_step("slack_webhook", data: { message: "received" })
    workflow_run.reload

    assert_equal 1, workflow_run.steps.length
    step = workflow_run.steps.first
    assert_equal "slack_webhook", step["name"]
    assert_equal({ "message" => "received" }, step["data"])
    assert_not_nil step["completed_at"]
  end

  test "fail_step should record failed step" do
    workflow_run = ThreadAgent::WorkflowRun.create!(@valid_attributes)

    workflow_run.fail_step("openai_process", "API timeout")
    workflow_run.reload

    assert_equal 1, workflow_run.steps.length
    step = workflow_run.steps.first
    assert_equal "openai_process", step["name"]
    assert_equal "API timeout", step["error"]
    assert_not_nil step["failed_at"]
  end

  test "current_step should return last step" do
    workflow_run = ThreadAgent::WorkflowRun.create!(@valid_attributes)

    # No steps initially
    assert_nil workflow_run.current_step

    # Add first step
    workflow_run.add_step("slack_webhook")
    assert_equal "slack_webhook", workflow_run.current_step["name"]

    # Add second step - should become current
    workflow_run.add_step("openai_process")
    assert_equal "openai_process", workflow_run.current_step["name"]
  end

  test "can mix successful and failed steps" do
    workflow_run = ThreadAgent::WorkflowRun.create!(@valid_attributes)

    workflow_run.add_step("slack_webhook", data: { modal_sent: true })
    workflow_run.fail_step("openai_process", "Rate limit exceeded")
    workflow_run.reload

    assert_equal 2, workflow_run.steps.length

    # First step succeeded
    slack_step = workflow_run.steps.first
    assert_equal "slack_webhook", slack_step["name"]
    assert_not_nil slack_step["completed_at"]
    assert_nil slack_step["error"]

    # Second step failed
    openai_step = workflow_run.steps.last
    assert_equal "openai_process", openai_step["name"]
    assert_not_nil openai_step["failed_at"]
    assert_equal "Rate limit exceeded", openai_step["error"]
  end
end
