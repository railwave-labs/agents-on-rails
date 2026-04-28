# frozen_string_literal: true

require "test_helper"

class Slack::EventDispatcherTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  ALLOWED_CHANNEL = "C_TRIAGE_001"
  OTHER_CHANNEL   = "C_OTHER_999"

  def setup
    @original_channels = ENV.fetch("TRIAGE_ALERT_SLACK_CHANNEL_IDS", nil)
    ENV["TRIAGE_ALERT_SLACK_CHANNEL_IDS"] = ALLOWED_CHANNEL
  end

  def teardown
    if @original_channels.nil?
      ENV.delete("TRIAGE_ALERT_SLACK_CHANNEL_IDS")
    else
      ENV["TRIAGE_ALERT_SLACK_CHANNEL_IDS"] = @original_channels
    end
  end

  test "ignores non-message events" do
    payload = { "event" => { "type" => "reaction_added", "channel" => ALLOWED_CHANNEL } }
    result = Slack::EventDispatcher.dispatch(payload)
    assert result.success?
    assert_equal :ignored, result.data
    assert_no_enqueued_jobs
  end

  test "ignores messages from bots (bot_id present)" do
    payload = {
      "event" => {
        "type"   => "message",
        "channel" => ALLOWED_CHANNEL,
        "bot_id"  => "B123456",
        "text"    => "bot says hi"
      }
    }
    result = Slack::EventDispatcher.dispatch(payload)
    assert result.success?
    assert_equal :ignored, result.data
    assert_no_enqueued_jobs
  end

  test "ignores bot_message subtype" do
    payload = {
      "event" => {
        "type"    => "message",
        "channel" => ALLOWED_CHANNEL,
        "subtype" => "bot_message",
        "text"    => "bot says hi"
      }
    }
    result = Slack::EventDispatcher.dispatch(payload)
    assert result.success?
    assert_equal :ignored, result.data
    assert_no_enqueued_jobs
  end

  test "ignores messages from channels not in the allowlist" do
    payload = {
      "event" => {
        "type"    => "message",
        "channel" => OTHER_CHANNEL,
        "user"    => "U123456",
        "text"    => "real user message"
      }
    }
    result = Slack::EventDispatcher.dispatch(payload)
    assert result.success?
    assert_equal :ignored, result.data
    assert_no_enqueued_jobs
  end

  test "enqueues AnalyzeJob for allowlisted channel with real user message" do
    payload = {
      "event" => {
        "type"    => "message",
        "channel" => ALLOWED_CHANNEL,
        "user"    => "U123456",
        "text"    => "Error rate spiked on checkout",
        "ts"      => "1234567890.123456"
      }
    }

    assert_enqueued_with(job: Agents::Triage::AnalyzeJob) do
      result = Slack::EventDispatcher.dispatch(payload)
      assert result.success?
      assert_equal :enqueued_triage, result.data
    end
  end

  test "empty TRIAGE_ALERT_SLACK_CHANNEL_IDS treats every channel as off-list" do
    ENV["TRIAGE_ALERT_SLACK_CHANNEL_IDS"] = ""
    payload = {
      "event" => {
        "type"    => "message",
        "channel" => ALLOWED_CHANNEL,
        "user"    => "U123456",
        "text"    => "alert!"
      }
    }
    result = Slack::EventDispatcher.dispatch(payload)
    assert_equal :ignored, result.data
    assert_no_enqueued_jobs
  end

  test "supports multiple channels in allowlist" do
    ENV["TRIAGE_ALERT_SLACK_CHANNEL_IDS"] = "C_FIRST, #{ALLOWED_CHANNEL}, C_THIRD"
    payload = {
      "event" => {
        "type"    => "message",
        "channel" => ALLOWED_CHANNEL,
        "user"    => "U123456",
        "text"    => "alert!"
      }
    }
    assert_enqueued_with(job: Agents::Triage::AnalyzeJob) do
      Slack::EventDispatcher.dispatch(payload)
    end
  end

  test "missing event key is treated as ignored" do
    payload = { "type" => "event_callback" }
    result  = Slack::EventDispatcher.dispatch(payload)
    assert_equal :ignored, result.data
    assert_no_enqueued_jobs
  end
end
