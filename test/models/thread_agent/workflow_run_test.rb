# frozen_string_literal: true

require "test_helper"

module ThreadAgent
  class WorkflowRunTest < ActiveSupport::TestCase
    test "should create workflow run with valid attributes" do
      workflow_run = build(:workflow_run)
      assert workflow_run.valid?
      assert workflow_run.save
    end

    test "should require workflow_name" do
      workflow_run = build(:workflow_run, workflow_name: nil)
      assert_not workflow_run.valid?
      assert_includes workflow_run.errors[:workflow_name], "can't be blank"
    end

    test "should require status" do
      workflow_run = build(:workflow_run, status: nil)
      workflow_run.status = nil
      assert_not workflow_run.valid?
      assert_includes workflow_run.errors[:status], "can't be blank"
    end

    test "should validate status inclusion" do
      assert_raises(ArgumentError) do
        build(:workflow_run, status: "invalid_status")
      end
    end

    test "should validate workflow_name length" do
      workflow_run = build(:workflow_run, workflow_name: "a" * 256)
      assert_not workflow_run.valid?
      assert_includes workflow_run.errors[:workflow_name], "is too long (maximum is 255 characters)"
    end

    test "should validate error_message length" do
      workflow_run = build(:workflow_run, error_message: "a" * 2001)
      assert_not workflow_run.valid?
      assert_includes workflow_run.errors[:error_message], "is too long (maximum is 2000 characters)"
    end

    test "should have correct default status" do
      workflow_run = WorkflowRun.new(workflow_name: "test")
      assert_equal "pending", workflow_run.status
    end

    test "should have correct enums" do
      expected_statuses = %w[pending running completed failed cancelled]
      assert_equal expected_statuses, ThreadAgent::WorkflowRun.statuses.keys
    end

    # Scope tests
    test "should have correct scopes" do
      pending_run = create(:workflow_run, status: "pending")
      running_run = create(:workflow_run, :running)
      completed_run = create(:workflow_run, :completed)
      failed_run = create(:workflow_run, :failed)
      cancelled_run = create(:workflow_run, :cancelled)

      assert_includes ThreadAgent::WorkflowRun.pending, pending_run
      assert_includes ThreadAgent::WorkflowRun.running, running_run
      assert_includes ThreadAgent::WorkflowRun.completed, completed_run
      assert_includes ThreadAgent::WorkflowRun.failed, failed_run
      assert_includes ThreadAgent::WorkflowRun.cancelled, cancelled_run

      assert_not_includes ThreadAgent::WorkflowRun.pending, running_run
      assert_not_includes ThreadAgent::WorkflowRun.running, pending_run
    end

    # Instance method tests for status checks
    test "status query methods should work correctly" do
      pending_run = create(:workflow_run, status: "pending")
      running_run = create(:workflow_run, :running)
      completed_run = create(:workflow_run, :completed)

      assert pending_run.pending?
      assert_not pending_run.running?
      assert_not pending_run.completed?

      assert_not running_run.pending?
      assert running_run.running?
      assert_not running_run.completed?

      assert_not completed_run.pending?
      assert_not completed_run.running?
      assert completed_run.completed?
    end

    test "should set correct table name" do
      assert_equal "thread_agent_workflow_runs", ThreadAgent::WorkflowRun.table_name
    end
  end
end
