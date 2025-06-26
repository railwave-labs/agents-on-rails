# frozen_string_literal: true

require_relative "thread_agent/result"
require_relative "thread_agent/error_handler"

# ThreadAgent provides a comprehensive system for processing Slack threads
# and creating Notion pages via webhooks.
#
# The system includes:
# - Webhook handling for Slack events
# - Background job processing with WorkflowOrchestrator
# - Service layer integrations for Slack, OpenAI, and Notion APIs
# - Comprehensive error handling with hierarchical error classes
# - Result pattern for consistent success/failure handling
#
# Error Handling:
# ThreadAgent implements a standardized error handling system with:
# - Hierarchical error classes inheriting from ThreadAgent::Error
# - Centralized error processing via ThreadAgent::ErrorHandler
# - Structured logging with JSON format and contextual information
# - Automatic retry capabilities for transient errors
# - Service-specific error classification (Slack, OpenAI, Notion)
#
# Usage:
#   # Configure the system
#   ThreadAgent.configure do |config|
#     config.slack_bot_token = "xoxb-your-token"
#     config.openai_api_key = "sk-your-key"
#     config.notion_token = "secret_your-token"
#   end
#
#   # Process webhooks (typically via Rails controller)
#   result = ThreadAgent::WorkflowOrchestrator.execute_workflow(workflow_run)
#
#   # Handle results
#   if result.success?
#     # Process successful result
#   else
#     # Handle error with appropriate retry logic
#     error = result.error
#     if error.retryable?
#       # Implement retry with backoff
#     end
#   end
#
# For detailed error handling patterns, see docs/error_handling.md
module ThreadAgent
  # Notion API timeout in seconds
  NOTION_TIMEOUT = 30

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configuration=(config)
      @configuration = config
    end

    def configure
      yield(configuration) if block_given?
      configuration
    end

    def config
      configuration
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end

  # Configuration management for ThreadAgent
  #
  # Handles environment variable loading and validation for all
  # required services (Slack, OpenAI, Notion).
  class Configuration
    attr_accessor :slack_client_id, :slack_client_secret, :slack_signing_secret, :slack_bot_token,
                  :openai_api_key, :openai_model,
                  :notion_client_id, :notion_client_secret, :notion_token,
                  :default_timeout, :max_retries

    def initialize
      @slack_client_id = ENV.fetch("THREAD_AGENT_SLACK_CLIENT_ID", nil)
      @slack_client_secret = ENV.fetch("THREAD_AGENT_SLACK_CLIENT_SECRET", nil)
      @slack_signing_secret = ENV.fetch("THREAD_AGENT_SLACK_SIGNING_SECRET", nil)
      @slack_bot_token = ENV.fetch("THREAD_AGENT_SLACK_BOT_TOKEN", nil)
      @openai_api_key = ENV.fetch("THREAD_AGENT_OPENAI_API_KEY", nil)
      @openai_model = ENV.fetch("THREAD_AGENT_OPENAI_MODEL", "gpt-4o-mini")
      @notion_client_id = ENV.fetch("THREAD_AGENT_NOTION_CLIENT_ID", nil)
      @notion_client_secret = ENV.fetch("THREAD_AGENT_NOTION_CLIENT_SECRET", nil)
      @notion_token = ENV.fetch("THREAD_AGENT_NOTION_TOKEN", nil)
      @default_timeout = ENV.fetch("THREAD_AGENT_DEFAULT_TIMEOUT", "30").to_i
      @max_retries = ENV.fetch("THREAD_AGENT_MAX_RETRIES", "3").to_i
    end

    def slack_configured?
      !slack_client_id.nil? && !slack_client_id.empty? &&
        !slack_client_secret.nil? && !slack_client_secret.empty? &&
        !slack_signing_secret.nil? && !slack_signing_secret.empty?
    end

    def openai_configured?
      !openai_api_key.nil? && !openai_api_key.empty?
    end

    def notion_configured?
      # Check for either OAuth flow (client_id + client_secret) or direct token
      oauth_configured = !notion_client_id.nil? && !notion_client_id.empty? &&
                         !notion_client_secret.nil? && !notion_client_secret.empty?
      token_configured = !notion_token.nil? && !notion_token.empty?

      oauth_configured || token_configured
    end

    def fully_configured?
      slack_configured? && openai_configured? && notion_configured?
    end
  end

  # Base error class for all ThreadAgent errors
  #
  # Provides standardized error handling with:
  # - Unique error codes for classification
  # - Contextual information for debugging
  # - Retry capability flags
  # - Structured hash representation
  #
  # @param message [String] Human-readable error message
  # @param code [String] Unique error code for classification
  # @param context [Hash] Additional context data
  # @param retryable [Boolean] Whether this error can be retried
  class Error < StandardError
    attr_reader :code, :context, :retryable

    def initialize(message = nil, code: nil, context: {}, retryable: true)
      super(message)
      @code = code
      @context = context || {}
      @retryable = retryable
    end

    def retryable?
      @retryable
    end

    def to_h
      {
        code: code,
        message: message,
        context: context,
        retryable: retryable?
      }
    end
  end

  # Configuration and setup errors (non-retryable)
  class ConfigurationError < Error
    def initialize(message = nil, code: nil, context: {}, retryable: false)
      super(message, code: code || "configuration.invalid", context: context, retryable: retryable)
    end
  end

  # Slack API and webhook errors
  class SlackError < Error
    def initialize(message = nil, code: nil, context: {}, retryable: true)
      super(message, code: code || "slack.request.failed", context: context, retryable: retryable)
    end
  end

  # Slack authentication errors (non-retryable)
  class SlackAuthError < SlackError
    def initialize(message = nil, code: nil, context: {}, retryable: false)
      super(message, code: code || "slack.auth.invalid", context: context, retryable: retryable)
    end
  end

  # Slack rate limit errors (retryable with backoff)
  class SlackRateLimitError < SlackError
    def initialize(message = nil, code: nil, context: {}, retryable: true)
      super(message, code: code || "slack.rate_limit.exceeded", context: context, retryable: retryable)
    end
  end

  # OpenAI API errors
  class OpenaiError < Error
    def initialize(message = nil, code: nil, context: {}, retryable: true)
      super(message, code: code || "openai.request.failed", context: context, retryable: retryable)
    end
  end

  # OpenAI authentication errors (non-retryable)
  class OpenaiAuthError < OpenaiError
    def initialize(message = nil, code: nil, context: {}, retryable: false)
      super(message, code: code || "openai.auth.invalid", context: context, retryable: retryable)
    end
  end

  # OpenAI rate limit errors (retryable with backoff)
  class OpenaiRateLimitError < OpenaiError
    def initialize(message = nil, code: nil, context: {}, retryable: true)
      super(message, code: code || "openai.rate_limit.exceeded", context: context, retryable: retryable)
    end
  end

  # Notion API errors
  class NotionError < Error
    def initialize(message = nil, code: nil, context: {}, retryable: true)
      super(message, code: code || "notion.request.failed", context: context, retryable: retryable)
    end
  end

  # Notion authentication errors (non-retryable)
  class NotionAuthError < NotionError
    def initialize(message = nil, code: nil, context: {}, retryable: false)
      super(message, code: code || "notion.auth.invalid", context: context, retryable: retryable)
    end
  end

  # Notion rate limit errors (retryable with backoff)
  class NotionRateLimitError < NotionError
    def initialize(message = nil, code: nil, context: {}, retryable: true)
      super(message, code: code || "notion.rate_limit.exceeded", context: context, retryable: retryable)
    end
  end

  # Data validation and transformation errors (non-retryable)
  class ValidationError < Error
    def initialize(message = nil, code: nil, context: {}, retryable: false)
      super(message, code: code || "validation.failed", context: context, retryable: retryable)
    end
  end

  # JSON parsing errors (non-retryable)
  class ParseError < Error
    def initialize(message = nil, code: nil, context: {}, retryable: false)
      super(message, code: code || "parse.json.failed", context: context, retryable: retryable)
    end
  end

  # Timeout errors (retryable)
  class TimeoutError < Error
    def initialize(message = nil, code: nil, context: {}, retryable: true)
      super(message, code: code || "request.timeout", context: context, retryable: retryable)
    end
  end

  # Network connection errors (retryable)
  class ConnectionError < Error
    def initialize(message = nil, code: nil, context: {}, retryable: true)
      super(message, code: code || "connection.failed", context: context, retryable: retryable)
    end
  end
end
