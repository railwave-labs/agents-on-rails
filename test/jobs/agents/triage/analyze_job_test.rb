# frozen_string_literal: true

require "test_helper"

class Agents::Triage::AnalyzeJobTest < ActiveJob::TestCase
  TRIAGE_JSON = <<~JSON.strip
    {
      "severity": "medium",
      "hypothesis": "Error rate spike on checkout",
      "suggested_next_step": "Investigate logs",
      "context_links": [],
      "confidence": 0.7
    }
  JSON

  def setup
    Anthropic::McpServers.stubs(:load).returns([])

    tool_loop = mock("Anthropic::ToolLoop")
    tool_loop.stubs(:run).returns(TRIAGE_JSON)
    Anthropic::ToolLoop.stubs(:new).returns(tool_loop)

    slack_reply = mock("PostSlackReply")
    slack_reply.stubs(:call).returns(Result.success(nil))
    Agents::Triage::Actions::PostSlackReply.stubs(:new).returns(slack_reply)
  end

  def sample_payload
    {
      "type"  => "event_callback",
      "event" => {
        "type"    => "message",
        "channel" => "C_TRIAGE_001",
        "user"    => "U123456",
        "text"    => "Error rate spiked on checkout",
        "ts"      => "1234567890.123456"
      }
    }
  end

  test "creates an AgentRun with kind triage" do
    assert_difference("AgentRun.count", 1) do
      Agents::Triage::AnalyzeJob.perform_now(slack_event_payload: sample_payload)
    end

    run = AgentRun.last
    assert_equal "triage", run.kind
    assert_equal "triage", run.workflow_name
    assert_equal "C_TRIAGE_001", run.slack_channel_id
    assert_equal "1234567890.123456", run.slack_thread_ts
  end

  test "marks AgentRun completed after stub orchestrator" do
    Agents::Triage::AnalyzeJob.perform_now(slack_event_payload: sample_payload)
    run = AgentRun.last
    assert run.completed?
  end

  test "stores slack event in input_data" do
    Agents::Triage::AnalyzeJob.perform_now(slack_event_payload: sample_payload)
    run = AgentRun.last
    assert_equal({ "slack_event" => sample_payload }, run.input_data)
  end

  test "can be enqueued" do
    assert_enqueued_with(job: Agents::Triage::AnalyzeJob) do
      Agents::Triage::AnalyzeJob.perform_later(slack_event_payload: sample_payload)
    end
  end
end
