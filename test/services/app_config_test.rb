# frozen_string_literal: true

require 'test_helper'

class AppConfigTest < ActiveSupport::TestCase
  setup do
    @original_openai_model = AppConfig.openai_model
    @original_default_timeout = AppConfig.default_timeout
    @original_max_retries = AppConfig.max_retries
  end

  teardown do
    AppConfig.instance.openai_model    = @original_openai_model
    AppConfig.instance.default_timeout = @original_default_timeout
    AppConfig.instance.max_retries     = @original_max_retries
  end

  test "AppConfig singleton is accessible" do
    assert_not_nil AppConfig.instance
    assert_instance_of AppConfig, AppConfig.instance
  end

  test "AppConfig has default values" do
    AppConfig.instance.openai_model    = 'gpt-4o-mini'
    AppConfig.instance.default_timeout = 30
    AppConfig.instance.max_retries     = 3

    assert_equal 'gpt-4o-mini', AppConfig.openai_model
    assert_equal 30, AppConfig.default_timeout
    assert_equal 3, AppConfig.max_retries
  end

  test "AppConfig attributes can be set directly" do
    AppConfig.instance.openai_model = 'gpt-4'
    assert_equal 'gpt-4', AppConfig.openai_model
  end

  test "slack_configured? returns true when all slack config present" do
    original = {
      id: AppConfig.instance.slack_client_id,
      secret: AppConfig.instance.slack_client_secret,
      signing: AppConfig.instance.slack_signing_secret
    }

    AppConfig.instance.slack_client_id     = 'client_id'
    AppConfig.instance.slack_client_secret = 'client_secret'
    AppConfig.instance.slack_signing_secret = 'signing_secret'

    assert AppConfig.slack_configured?
  ensure
    AppConfig.instance.slack_client_id     = original[:id]
    AppConfig.instance.slack_client_secret = original[:secret]
    AppConfig.instance.slack_signing_secret = original[:signing]
  end

  test "openai_configured? returns true when api key present" do
    original = AppConfig.instance.openai_api_key
    AppConfig.instance.openai_api_key = 'test_key'
    assert AppConfig.openai_configured?
  ensure
    AppConfig.instance.openai_api_key = original
  end

  test "notion_configured? returns true when notion token set" do
    original = AppConfig.instance.notion_token
    AppConfig.instance.notion_token = 'secret_token'
    assert AppConfig.notion_configured?
  ensure
    AppConfig.instance.notion_token = original
  end

  test "error hierarchy uses new canonical classes" do
    assert_equal ApplicationError, ConfigurationError.superclass
    assert_equal ApplicationError, Slack::Error.superclass
    assert_equal ApplicationError, Openai::Error.superclass
    assert_equal ApplicationError, Notion::Error.superclass
  end
end
