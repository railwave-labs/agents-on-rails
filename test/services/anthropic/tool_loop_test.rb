# frozen_string_literal: true

require "test_helper"
require_dependency "anthropic/error"

class Anthropic::ToolLoopTest < ActiveSupport::TestCase
  SAMPLE_JSON_RESPONSE = <<~JSON.strip
    {
      "severity": "high",
      "hypothesis": "nil pointer in checkout flow",
      "suggested_next_step": "Check the nil guard on CartService#total",
      "context_links": ["https://sentry.io/issues/999"],
      "confidence": 0.85
    }
  JSON

  # A lightweight struct that mimics the Anthropic::Message SDK response
  # so tests don't depend on the real HTTP layer.
  class FakeTextBlock
    attr_reader :type, :text

    def initialize(text)
      @type = "text"
      @text = text
    end

    def respond_to?(method, include_private = false)
      %i[type text].include?(method) || super
    end
  end

  class FakeMcpToolUseBlock
    attr_reader :type, :server_name, :name, :input

    def initialize
      @type        = "mcp_tool_use"
      @server_name = "sentry"
      @name        = "get_issue"
      @input       = { "issue_id" => "999" }
    end
  end

  class FakeMcpToolResultBlock
    attr_reader :type, :tool_use_id, :is_error, :content

    def initialize
      @type        = "mcp_tool_result"
      @tool_use_id = "tu_123"
      @is_error    = false
      @content     = [{ "type" => "text", "text" => "Found issue" }]
    end
  end

  class FakeUsage
    attr_reader :input_tokens, :output_tokens

    def initialize(input: 100, output: 50)
      @input_tokens  = input
      @output_tokens = output
    end
  end

  class FakeResponse
    attr_reader :content, :usage

    def initialize(content:, usage: FakeUsage.new)
      @content = content
      @usage   = usage
    end
  end

  def text_response(extra_blocks: [])
    FakeResponse.new(
      content: extra_blocks + [FakeTextBlock.new(SAMPLE_JSON_RESPONSE)],
      usage:   FakeUsage.new(input: 100, output: 50)
    )
  end

  def mock_client(response)
    client = mock("Anthropic::ApiClient")
    client.expects(:messages_create).returns(response)
    client
  end

  test "returns final text from a plain text response" do
    loop = Anthropic::ToolLoop.new(client: mock_client(text_response), on_step: ->(_) {})
    text = loop.run(system: "sys", messages: [{ role: "user", content: "alert!" }])
    assert_equal SAMPLE_JSON_RESPONSE, text
  end

  test "calls on_step for mcp_tool_use blocks" do
    steps = []
    on_step = ->(step) { steps << step }

    loop = Anthropic::ToolLoop.new(
      client:  mock_client(text_response(extra_blocks: [FakeMcpToolUseBlock.new])),
      on_step: on_step
    )
    loop.run(system: "sys", messages: [{ role: "user", content: "alert!" }])

    mcp_step = steps.find { |s| s[:name] == "mcp_tool_use" }
    assert_not_nil mcp_step
    assert_equal "sentry", mcp_step[:data][:server]
    assert_equal "get_issue", mcp_step[:data][:name]
  end

  test "calls on_step for mcp_tool_result blocks" do
    steps = []
    on_step = ->(step) { steps << step }

    loop = Anthropic::ToolLoop.new(
      client:  mock_client(text_response(extra_blocks: [FakeMcpToolResultBlock.new])),
      on_step: on_step
    )
    loop.run(system: "sys", messages: [{ role: "user", content: "alert!" }])

    result_step = steps.find { |s| s[:name] == "mcp_tool_result" }
    assert_not_nil result_step
    assert_equal "tu_123", result_step[:data][:tool_use_id]
  end

  test "calls on_step for usage" do
    steps = []
    on_step = ->(step) { steps << step }

    loop = Anthropic::ToolLoop.new(client: mock_client(text_response), on_step: on_step)
    loop.run(system: "sys", messages: [{ role: "user", content: "alert!" }])

    usage_step = steps.find { |s| s[:name] == "usage" }
    assert_not_nil usage_step
    assert_equal 100, usage_step[:data]["input_tokens"]
    assert_equal 50, usage_step[:data]["output_tokens"]
  end

  test "raises ValidationError when response has no text content" do
    response = FakeResponse.new(content: [FakeMcpToolResultBlock.new])
    loop = Anthropic::ToolLoop.new(client: mock_client(response), on_step: ->(_) {})

    assert_raises(ValidationError) do
      loop.run(system: "sys", messages: [{ role: "user", content: "alert!" }])
    end
  end

  test "re-raises Anthropic::ApiRateLimitError from the client" do
    client = mock("Anthropic::ApiClient")
    client.expects(:messages_create).raises(Anthropic::ApiRateLimitError.new("rate limited"))

    loop = Anthropic::ToolLoop.new(client: client, on_step: ->(_) {})

    assert_raises(Anthropic::ApiRateLimitError) do
      loop.run(system: "sys", messages: [{ role: "user", content: "alert!" }])
    end
  end

  test "wraps unexpected StandardError in ApplicationError" do
    client = mock("Anthropic::ApiClient")
    client.expects(:messages_create).raises(SocketError.new("Connection refused"))

    loop = Anthropic::ToolLoop.new(client: client, on_step: ->(_) {})

    assert_raises(ApplicationError) do
      loop.run(system: "sys", messages: [{ role: "user", content: "alert!" }])
    end
  end

  test "does not include mcp_servers param when list is empty" do
    client = mock("Anthropic::ApiClient")
    client.expects(:messages_create).with(
      model:      AppConfig.anthropic_model,
      max_tokens: 4096,
      system:     "sys",
      messages:   [{ role: "user", content: "alert!" }]
    ).returns(text_response)

    loop = Anthropic::ToolLoop.new(client: client, mcp_servers: [], on_step: ->(_) {})
    loop.run(system: "sys", messages: [{ role: "user", content: "alert!" }])
  end
end
