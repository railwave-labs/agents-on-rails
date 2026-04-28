# frozen_string_literal: true

require "test_helper"
require_dependency "anthropic/error"

class Agents::Triage::OrchestratorTest < ActiveSupport::TestCase
  TRIAGE_JSON = <<~JSON.strip
    {
      "severity": "high",
      "hypothesis": "Nil pointer in checkout flow",
      "suggested_next_step": "Check CartService#total nil guard",
      "context_links": ["https://sentry.io/issues/999"],
      "confidence": 0.85
    }
  JSON

  def setup
    @agent_run = AgentRun.create_for_kind(
      :triage,
      workflow_name:    "triage",
      slack_channel_id: "C_TRIAGE_001",
      slack_thread_ts:  "1234567890.123456",
      input_data:       { slack_event: { "event" => { "type" => "message", "text" => "alert!", "channel" => "C_TRIAGE_001", "ts" => "1234567890.123456" } } }
    )
    @agent_run.mark_started!

    Anthropic::McpServers.stubs(:load).returns([])
  end

  def stub_tool_loop_with(text)
    tool_loop = mock("Anthropic::ToolLoop")
    tool_loop.expects(:run).returns(text)
    Anthropic::ToolLoop.stubs(:new).returns(tool_loop)

    slack_reply = mock("PostSlackReply")
    slack_reply.stubs(:call).returns(Result.success(nil))
    Agents::Triage::Actions::PostSlackReply.stubs(:new).returns(slack_reply)

    tool_loop
  end

  test "returns a successful Result on happy path" do
    stub_tool_loop_with(TRIAGE_JSON)
    result = Agents::Triage::Orchestrator.execute(@agent_run)
    assert result.success?
  end

  test "marks AgentRun as completed on happy path" do
    stub_tool_loop_with(TRIAGE_JSON)
    Agents::Triage::Orchestrator.execute(@agent_run)
    assert @agent_run.reload.completed?
  end

  test "records triage_started and triage_parsed steps" do
    stub_tool_loop_with(TRIAGE_JSON)
    Agents::Triage::Orchestrator.execute(@agent_run)
    step_names = @agent_run.reload.steps.map { |s| s["name"] }
    assert_includes step_names, "triage_started"
    assert_includes step_names, "triage_parsed"
  end

  test "output_data matches parsed payload" do
    stub_tool_loop_with(TRIAGE_JSON)
    Agents::Triage::Orchestrator.execute(@agent_run)
    output = @agent_run.reload.output_data
    assert_equal "high", output["severity"]
    assert_equal 0.85, output["confidence"]
  end

  test "marks run failed when ToolLoop raises ApplicationError" do
    tool_loop = mock("Anthropic::ToolLoop")
    tool_loop.expects(:run).raises(Anthropic::Error.new("Anthropic error"))
    Anthropic::ToolLoop.stubs(:new).returns(tool_loop)

    Agents::Triage::Orchestrator.execute(@agent_run)

    assert @agent_run.reload.failed?
    assert_includes @agent_run.error_message, "Anthropic error"
  end

  test "marks run failed when StructuredResponse raises ValidationError" do
    stub_tool_loop_with("this is not json at all {{{{")
    Agents::Triage::Orchestrator.execute(@agent_run)
    assert @agent_run.reload.failed?
  end

  test "marks run failed when StructuredResponse raises ServiceParseError" do
    stub_tool_loop_with("{ bad json }")
    Agents::Triage::Orchestrator.execute(@agent_run)
    assert @agent_run.reload.failed?
  end
end
