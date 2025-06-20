# frozen_string_literal: true

require "test_helper"

class ThreadAgent::SlackServiceTest < ActiveSupport::TestCase
  test "initializes with valid bot token" do
    service = ThreadAgent::SlackService.new(bot_token: "xoxb-valid-token")
    assert_equal "xoxb-valid-token", service.bot_token
  end

  test "raises error with missing bot token" do
    assert_raises(ThreadAgent::SlackError) do
      ThreadAgent::SlackService.new(bot_token: nil)
    end
  end

  test "raises error with empty bot token" do
    assert_raises(ThreadAgent::SlackError) do
      ThreadAgent::SlackService.new(bot_token: "")
    end
  end

  test "uses ThreadAgent configuration by default" do
    # Mock the configuration
    original_config = ThreadAgent.configuration.slack_bot_token
    ThreadAgent.configuration.slack_bot_token = "xoxb-config-token"

    service = ThreadAgent::SlackService.new
    assert_equal "xoxb-config-token", service.bot_token

    # Restore original config
    ThreadAgent.configuration.slack_bot_token = original_config
  end

  test "raises error when ThreadAgent configuration has no bot token" do
    # Mock the configuration to return nil
    original_config = ThreadAgent.configuration.slack_bot_token
    ThreadAgent.configuration.slack_bot_token = nil

    assert_raises(ThreadAgent::SlackError) do
      ThreadAgent::SlackService.new
    end

    # Restore original config
    ThreadAgent.configuration.slack_bot_token = original_config
  end
end
