# frozen_string_literal: true

require "test_helper"

class Agents::Triage::PromptBuilderTest < ActiveSupport::TestCase
  def sample_event
    {
      "type"    => "message",
      "channel" => "C_TRIAGE_001",
      "user"    => "U123456",
      "text"    => "Error rate spiked on checkout. Sentry: https://sentry.io/issues/12345",
      "ts"      => "1234567890.123456"
    }
  end

  def agent_run_with_event
    run = AgentRun.create_for_kind(
      :triage,
      workflow_name:    "triage",
      slack_channel_id: "C_TRIAGE_001",
      slack_thread_ts:  "1234567890.123456",
      input_data: { slack_event: { "event" => sample_event } }
    )
    run.mark_started!
    run
  end

  test "returns a hash with system and messages keys" do
    result = Agents::Triage::PromptBuilder.build(agent_run: agent_run_with_event)
    assert result.key?(:system)
    assert result.key?(:messages)
  end

  test "system prompt contains playbook content" do
    result = Agents::Triage::PromptBuilder.build(agent_run: agent_run_with_event)
    assert_includes result[:system], "Triage Playbook"
  end

  test "system prompt contains output schema instruction" do
    result = Agents::Triage::PromptBuilder.build(agent_run: agent_run_with_event)
    assert_includes result[:system], '"severity"'
    assert_includes result[:system], '"hypothesis"'
    assert_includes result[:system], '"confidence"'
  end

  test "system prompt contains tool-use guidance" do
    result = Agents::Triage::PromptBuilder.build(agent_run: agent_run_with_event)
    assert_includes result[:system], "Sentry MCP"
    assert_includes result[:system], "GitHub MCP"
  end

  test "messages array has a single user message" do
    result = Agents::Triage::PromptBuilder.build(agent_run: agent_run_with_event)
    assert_equal 1, result[:messages].length
    assert_equal "user", result[:messages].first[:role]
  end

  test "user prompt contains channel and timestamp" do
    result = Agents::Triage::PromptBuilder.build(agent_run: agent_run_with_event)
    user_content = result[:messages].first[:content]
    assert_includes user_content, "C_TRIAGE_001"
    assert_includes user_content, "1234567890.123456"
  end

  test "user prompt contains Slack permalink" do
    result = Agents::Triage::PromptBuilder.build(agent_run: agent_run_with_event)
    user_content = result[:messages].first[:content]
    assert_includes user_content, "slack.com/archives/C_TRIAGE_001"
    assert_includes user_content, "p1234567890-123456"
  end

  test "user prompt contains alert message text" do
    result = Agents::Triage::PromptBuilder.build(agent_run: agent_run_with_event)
    user_content = result[:messages].first[:content]
    assert_includes user_content, "Error rate spiked on checkout"
  end

  test "handles missing event gracefully" do
    run = AgentRun.create_for_kind(:triage, workflow_name: "triage")
    run.mark_started!
    result = Agents::Triage::PromptBuilder.build(agent_run: run)
    assert result[:system].present?
    assert result[:messages].first[:content].present?
  end
end
