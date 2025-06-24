# frozen_string_literal: true

require "test_helper"

class ThreadAgentInitializerTest < ActiveSupport::TestCase
  def setup
    # Store original environment values
    @original_env = {
      "THREAD_AGENT_DEFAULT_TIMEOUT" => ENV["THREAD_AGENT_DEFAULT_TIMEOUT"],
      "THREAD_AGENT_MAX_RETRIES" => ENV["THREAD_AGENT_MAX_RETRIES"],
      "THREAD_AGENT_OPENAI_MODEL" => ENV["THREAD_AGENT_OPENAI_MODEL"],
      "THREAD_AGENT_OPENAI_API_KEY" => ENV["THREAD_AGENT_OPENAI_API_KEY"],
      "THREAD_AGENT_SLACK_CLIENT_ID" => ENV["THREAD_AGENT_SLACK_CLIENT_ID"],
      "THREAD_AGENT_SLACK_CLIENT_SECRET" => ENV["THREAD_AGENT_SLACK_CLIENT_SECRET"],
      "THREAD_AGENT_SLACK_SIGNING_SECRET" => ENV["THREAD_AGENT_SLACK_SIGNING_SECRET"],
      "THREAD_AGENT_SLACK_BOT_TOKEN" => ENV["THREAD_AGENT_SLACK_BOT_TOKEN"],
      "THREAD_AGENT_NOTION_CLIENT_ID" => ENV["THREAD_AGENT_NOTION_CLIENT_ID"],
      "THREAD_AGENT_NOTION_CLIENT_SECRET" => ENV["THREAD_AGENT_NOTION_CLIENT_SECRET"],
      "THREAD_AGENT_NOTION_TOKEN" => ENV["THREAD_AGENT_NOTION_TOKEN"]
    }
  end

  def teardown
    # Restore original environment values
    @original_env.each do |key, value|
      if value
        ENV[key] = value
      else
        ENV.delete(key)
      end
    end
    # Reset configuration after each test
    ThreadAgent.reset_configuration!
  end

  test "ThreadAgent initializer loads and configures ThreadAgent correctly" do
    # Clear environment variables to test defaults
    clear_environment_variables

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
    # Clear environment first
    clear_environment_variables

    # Test that configuration reads from environment variables correctly
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
      # Clear test environment variables
      ENV.delete("THREAD_AGENT_DEFAULT_TIMEOUT")
      ENV.delete("THREAD_AGENT_OPENAI_MODEL")
      ThreadAgent.reset_configuration!
    end
  end

  test "ThreadAgent configuration methods work correctly" do
    # Clear environment variables to ensure no configuration is present
    clear_environment_variables

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
    # Clear environment first
    clear_environment_variables

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

  private

  def clear_environment_variables
    @original_env.keys.each { |key| ENV.delete(key) }
    ThreadAgent.reset_configuration!
  end
end
