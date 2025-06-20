# frozen_string_literal: true

require "test_helper"

class ThreadAgentInitializerTest < ActiveSupport::TestCase
  test "ThreadAgent initializer loads and configures ThreadAgent correctly" do
    # Verify that ThreadAgent module is loaded
    assert_not_nil ThreadAgent

    # Verify that configuration is accessible
    assert_not_nil ThreadAgent.configuration
    assert_instance_of ThreadAgent::Configuration, ThreadAgent.configuration

    # Verify that configuration has expected defaults
    assert_equal 30, ThreadAgent.configuration.default_timeout
    assert_equal 3, ThreadAgent.configuration.max_retries
    assert_equal "gpt-4o-mini", ThreadAgent.configuration.openai_model
  end

  test "ThreadAgent configuration responds to environment variables" do
    # Test that configuration reads from environment variables correctly
    original_timeout = ENV["THREAD_AGENT_DEFAULT_TIMEOUT"]
    original_model = ENV["THREAD_AGENT_OPENAI_MODEL"]

    begin
      # Set test environment variables
      ENV["THREAD_AGENT_DEFAULT_TIMEOUT"] = "60"
      ENV["THREAD_AGENT_OPENAI_MODEL"] = "gpt-4"

      # Reset configuration to pick up new env vars
      ThreadAgent.reset_configuration!

      # Verify new values are loaded
      assert_equal 60, ThreadAgent.configuration.default_timeout
      assert_equal "gpt-4", ThreadAgent.configuration.openai_model
    ensure
      # Restore original environment
      ENV["THREAD_AGENT_DEFAULT_TIMEOUT"] = original_timeout
      ENV["THREAD_AGENT_OPENAI_MODEL"] = original_model
      ThreadAgent.reset_configuration!
    end
  end

  test "ThreadAgent configuration methods work correctly" do
    # Test configuration check methods
    assert_respond_to ThreadAgent.configuration, :slack_configured?
    assert_respond_to ThreadAgent.configuration, :openai_configured?
    assert_respond_to ThreadAgent.configuration, :notion_configured?
    assert_respond_to ThreadAgent.configuration, :fully_configured?

    # With no environment variables set, nothing should be configured
    assert_equal false, ThreadAgent.configuration.slack_configured?
    assert_equal false, ThreadAgent.configuration.openai_configured?
    assert_equal false, ThreadAgent.configuration.notion_configured?
    assert_equal false, ThreadAgent.configuration.fully_configured?
  end

  test "ThreadAgent configure block works" do
    # Test that the configure block pattern works
    ThreadAgent.configure do |config|
      config.default_timeout = 45
      config.max_retries = 5
    end

    assert_equal 45, ThreadAgent.configuration.default_timeout
    assert_equal 5, ThreadAgent.configuration.max_retries

    # Reset for other tests
    ThreadAgent.reset_configuration!
  end
end
