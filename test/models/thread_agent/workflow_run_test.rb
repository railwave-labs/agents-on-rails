# frozen_string_literal: true

require "test_helper"

module ThreadAgent
  class WorkflowRunTest < ActiveSupport::TestCase
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

    test "should validate slack_message_id length" do
      long_id = "a" * 256
      workflow_run = ThreadAgent::WorkflowRun.new(@valid_attributes.merge(slack_message_id: long_id))
      assert_not workflow_run.valid?
      assert_includes workflow_run.errors[:slack_message_id], "is too long (maximum is 255 characters)"
    end

    test "should validate slack_channel_id length" do
      long_id = "a" * 256
      workflow_run = ThreadAgent::WorkflowRun.new(@valid_attributes.merge(slack_channel_id: long_id))
      assert_not workflow_run.valid?
      assert_includes workflow_run.errors[:slack_channel_id], "is too long (maximum is 255 characters)"
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
      channel_run = ThreadAgent::WorkflowRun.create!(@valid_attributes.merge(slack_channel_id: "C123456"))
      message_run = ThreadAgent::WorkflowRun.create!(@valid_attributes.merge(slack_message_id: "1234567890.123456"))

      # Test scopes
      assert_includes ThreadAgent::WorkflowRun.active, pending_run
      assert_includes ThreadAgent::WorkflowRun.active, running_run
      assert_not_includes ThreadAgent::WorkflowRun.active, completed_run



      assert_includes ThreadAgent::WorkflowRun.by_workflow("test_workflow"), pending_run
      assert_not_includes ThreadAgent::WorkflowRun.by_workflow("test_workflow"), other_workflow_run

      assert_includes ThreadAgent::WorkflowRun.by_slack_channel("C123456"), channel_run
      assert_not_includes ThreadAgent::WorkflowRun.by_slack_channel("C123456"), pending_run

      assert_includes ThreadAgent::WorkflowRun.by_slack_message("1234567890.123456"), message_run
      assert_not_includes ThreadAgent::WorkflowRun.by_slack_message("1234567890.123456"), pending_run
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

    test "mark_completed! should update status, finished_at, and output_data" do
      workflow_run = ThreadAgent::WorkflowRun.create!(@valid_attributes)
      output_data = "Success result"

      workflow_run.mark_completed!(output_data)
      workflow_run.reload

      assert workflow_run.completed?
      assert_not_nil workflow_run.finished_at
      assert_equal output_data, workflow_run.output_data
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
      input_data = "test input data"
      workflow_run = ThreadAgent::WorkflowRun.create_for_workflow(
        "test_workflow",
        slack_message_id: "1234567890.123456",
        slack_channel_id: "C123456",
        input_data: input_data
      )

      assert workflow_run.persisted?
      assert_equal "test_workflow", workflow_run.workflow_name
      assert workflow_run.pending?
      assert_equal "1234567890.123456", workflow_run.slack_message_id
      assert_equal "C123456", workflow_run.slack_channel_id
      assert_equal input_data, workflow_run.input_data
      assert_equal [], workflow_run.steps
    end

    test "should set correct table name" do
      assert_equal "thread_agent_workflow_runs", ThreadAgent::WorkflowRun.table_name
    end

    test "should initialize with empty steps array" do
      workflow_run = ThreadAgent::WorkflowRun.create!(@valid_attributes)
      assert_equal [], workflow_run.steps
    end

    test "add_step should record completed step" do
      workflow_run = ThreadAgent::WorkflowRun.create!(@valid_attributes)

      workflow_run.add_step("process_slack_message", data: { channel: "general" })

      assert_equal 1, workflow_run.steps.length
      step = workflow_run.steps.first
      assert_equal "process_slack_message", step["name"]
      assert_not_nil step["completed_at"]
      assert_equal({ "channel" => "general" }, step["data"])
    end

    test "fail_step should record failed step" do
      workflow_run = ThreadAgent::WorkflowRun.create!(@valid_attributes)

      workflow_run.fail_step("openai_call", "API timeout")

      assert_equal 1, workflow_run.steps.length
      step = workflow_run.steps.first
      assert_equal "openai_call", step["name"]
      assert_not_nil step["failed_at"]
      assert_equal "API timeout", step["error"]
    end

    test "current_step should return last step" do
      workflow_run = ThreadAgent::WorkflowRun.create!(@valid_attributes)

      assert_nil workflow_run.current_step

      workflow_run.add_step("step1")
      workflow_run.add_step("step2")

      assert_equal "step2", workflow_run.current_step["name"]
    end

    test "can mix successful and failed steps" do
      workflow_run = ThreadAgent::WorkflowRun.create!(@valid_attributes)

      workflow_run.add_step("slack_received")
      workflow_run.fail_step("openai_call", "timeout")
      workflow_run.add_step("retry_openai")

      assert_equal 3, workflow_run.steps.length
      assert workflow_run.steps[0]["completed_at"]
      assert workflow_run.steps[1]["failed_at"]
      assert workflow_run.steps[2]["completed_at"]
    end
  end
end
