# frozen_string_literal: true

require "test_helper"

class Agents::Triage::Actions::PostSlackReplyTest < ActiveSupport::TestCase
  def setup
    @original_user_id = ENV.fetch("TRIAGE_ESCALATION_SLACK_USER_ID", nil)
    ENV["TRIAGE_ESCALATION_SLACK_USER_ID"] = "U_ONCALL_999"
  end

  def teardown
    if @original_user_id.nil?
      ENV.delete("TRIAGE_ESCALATION_SLACK_USER_ID")
    else
      ENV["TRIAGE_ESCALATION_SLACK_USER_ID"] = @original_user_id
    end
  end

  def build_payload(severity: "medium", confidence: 0.8, context_links: [])
    Agents::Triage::StructuredResponse::Payload.new(
      severity:            severity,
      hypothesis:          "Test hypothesis for #{severity}",
      suggested_next_step: "Fix it",
      context_links:       context_links,
      confidence:          confidence
    )
  end

  def build_agent_run(channel: "C_TRIAGE_001", thread_ts: "1234567890.123456")
    run = AgentRun.create_for_kind(:triage, workflow_name: "triage", slack_channel_id: channel, slack_thread_ts: thread_ts)
    run.mark_started!
    run
  end

  # A simple spy that captures calls to chat_postMessage
  class SlackApiSpy
    attr_reader :calls

    def initialize(error: nil)
      @calls = []
      @error = error
    end

    def chat_postMessage(**args)
      raise @error if @error

      @calls << args
      { "ts" => "1234567890.999" }
    end
  end

  def slack_service_with_spy(spy)
    service = mock("Slack::Service")
    service.stubs(:client).returns(spy)
    service
  end

  test "posts to the correct channel and thread_ts" do
    spy        = SlackApiSpy.new
    agent_run  = build_agent_run
    payload    = build_payload

    result = Agents::Triage::Actions::PostSlackReply.new(
      agent_run:     agent_run,
      payload:       payload,
      slack_service: slack_service_with_spy(spy)
    ).call

    assert result.success?
    assert_equal 1, spy.calls.length
    assert_equal "C_TRIAGE_001", spy.calls.first[:channel]
    assert_equal "1234567890.123456", spy.calls.first[:thread_ts]
  end

  test "does NOT tag escalation user for medium severity with high confidence" do
    spy = SlackApiSpy.new
    Agents::Triage::Actions::PostSlackReply.new(
      agent_run:     build_agent_run,
      payload:       build_payload(severity: "medium", confidence: 0.9),
      slack_service: slack_service_with_spy(spy)
    ).call

    assert_not_includes spy.calls.first[:text], "<@U_ONCALL_999>"
  end

  test "does NOT tag for info severity with high confidence" do
    spy = SlackApiSpy.new
    Agents::Triage::Actions::PostSlackReply.new(
      agent_run:     build_agent_run,
      payload:       build_payload(severity: "info", confidence: 0.95),
      slack_service: slack_service_with_spy(spy)
    ).call

    assert_not_includes spy.calls.first[:text], "<@U_ONCALL_999>"
  end

  test "tags escalation user for high severity" do
    spy = SlackApiSpy.new
    Agents::Triage::Actions::PostSlackReply.new(
      agent_run:     build_agent_run,
      payload:       build_payload(severity: "high", confidence: 0.9),
      slack_service: slack_service_with_spy(spy)
    ).call

    assert_includes spy.calls.first[:text], "<@U_ONCALL_999>"
  end

  test "tags escalation user for critical severity" do
    spy = SlackApiSpy.new
    Agents::Triage::Actions::PostSlackReply.new(
      agent_run:     build_agent_run,
      payload:       build_payload(severity: "critical", confidence: 0.9),
      slack_service: slack_service_with_spy(spy)
    ).call

    assert_includes spy.calls.first[:text], "<@U_ONCALL_999>"
  end

  test "tags escalation user when confidence < 0.6 even at low severity" do
    spy = SlackApiSpy.new
    Agents::Triage::Actions::PostSlackReply.new(
      agent_run:     build_agent_run,
      payload:       build_payload(severity: "low", confidence: 0.4),
      slack_service: slack_service_with_spy(spy)
    ).call

    assert_includes spy.calls.first[:text], "<@U_ONCALL_999>"
  end

  test "does not tag when TRIAGE_ESCALATION_SLACK_USER_ID is not set" do
    ENV.delete("TRIAGE_ESCALATION_SLACK_USER_ID")
    spy = SlackApiSpy.new
    Agents::Triage::Actions::PostSlackReply.new(
      agent_run:     build_agent_run,
      payload:       build_payload(severity: "critical", confidence: 0.9),
      slack_service: slack_service_with_spy(spy)
    ).call

    assert_not_includes spy.calls.first[:text].to_s, "<@"
  end

  test "records slack_reply_posted step on success" do
    spy       = SlackApiSpy.new
    agent_run = build_agent_run

    Agents::Triage::Actions::PostSlackReply.new(
      agent_run:     agent_run,
      payload:       build_payload,
      slack_service: slack_service_with_spy(spy)
    ).call

    step_names = agent_run.reload.steps.map { |s| s["name"] }
    assert_includes step_names, "slack_reply_posted"
  end

  test "returns Result.failure and records slack_reply_failed step when Slack API fails" do
    spy       = SlackApiSpy.new(error: StandardError.new("Slack down"))
    agent_run = build_agent_run

    result = Agents::Triage::Actions::PostSlackReply.new(
      agent_run:     agent_run,
      payload:       build_payload,
      slack_service: slack_service_with_spy(spy)
    ).call

    assert result.failure?
    step_names = agent_run.reload.steps.map { |s| s["name"] }
    assert_includes step_names, "slack_reply_failed"
  end
end
