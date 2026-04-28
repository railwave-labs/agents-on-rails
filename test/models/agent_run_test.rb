# frozen_string_literal: true

require "test_helper"

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
    workflow_run = AgentRun.new(workflow_name: "test")
    assert_equal "pending", workflow_run.status
  end

  test "should have correct enums" do
    expected_statuses = %w[pending running completed failed cancelled]
    assert_equal expected_statuses, AgentRun.statuses.keys
  end

  test "should have correct scopes" do
    pending_run = create(:workflow_run, status: "pending")
    running_run = create(:workflow_run, :running)
    completed_run = create(:workflow_run, :completed)
    failed_run = create(:workflow_run, :failed)
    cancelled_run = create(:workflow_run, :cancelled)

    assert_includes AgentRun.pending, pending_run
    assert_includes AgentRun.running, running_run
    assert_includes AgentRun.completed, completed_run
    assert_includes AgentRun.failed, failed_run
    assert_includes AgentRun.cancelled, cancelled_run

    assert_not_includes AgentRun.pending, running_run
    assert_not_includes AgentRun.running, pending_run
  end

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
    assert_equal "agent_runs", AgentRun.table_name
  end

  test "kind defaults to thread_capture" do
    run = create(:workflow_run)
    assert_equal "thread_capture", run.kind
    assert run.thread_capture?
  end

  test "kind can be set to triage" do
    run = create(:workflow_run, kind: "triage")
    assert run.triage?
  end

  test "kind must be valid enum value" do
    assert_raises(ArgumentError) { build(:workflow_run, kind: "unknown_kind") }
  end

  test "record_cost! accumulates cost_cents and token_usage" do
    run = create(:workflow_run)
    run.record_cost!(cents: 10, tokens: { input_tokens: 100, output_tokens: 50 })
    assert_equal 10, run.reload.cost_cents
    assert_equal({ "input_tokens" => 100, "output_tokens" => 50 }, run.token_usage)

    run.record_cost!(cents: 5, tokens: { input_tokens: 20, output_tokens: 10 })
    assert_equal 15, run.reload.cost_cents
    assert_equal({ "input_tokens" => 120, "output_tokens" => 60 }, run.token_usage)
  end

  test "create_for_kind builds agent run with the correct kind" do
    run = AgentRun.create_for_kind(:triage, workflow_name: "triage_run")
    assert run.persisted?
    assert_equal "triage", run.kind
    assert_equal "triage_run", run.workflow_name
  end

  test "create_for_workflow defaults kind to thread_capture" do
    run = AgentRun.create_for_workflow("my_workflow")
    assert_equal "thread_capture", run.kind
  end
end
