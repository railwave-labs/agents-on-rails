# frozen_string_literal: true

require "test_helper"

class ThreadAgent::Slack::RetryHandlerTest < ActiveSupport::TestCase
  test "initializes with default max retries" do
    handler = ThreadAgent::Slack::RetryHandler.new
    assert_equal 3, handler.max_retries
  end

  test "initializes with custom max retries" do
    handler = ThreadAgent::Slack::RetryHandler.new(max_retries: 5)
    assert_equal 5, handler.max_retries
  end

  test "executes block successfully without retries" do
    handler = ThreadAgent::Slack::RetryHandler.new
    result = handler.with_retries { "success" }
    assert_equal "success", result
  end

  test "retries on rate limit error with retry_after header" do
    handler = ThreadAgent::Slack::RetryHandler.new

    # Create rate limit error with mock response_metadata
    rate_limit_error = ::Slack::Web::Api::Errors::RateLimited.new("Rate limited")
    rate_limit_error.stubs(:response_metadata).returns({ "retry_after" => 1 })

    call_count = 0
    test_block = -> {
      call_count += 1
      raise rate_limit_error if call_count == 1
      "success"
    }

    handler.expects(:sleep).with(1).once

    result = handler.with_retries { test_block.call }
    assert_equal "success", result
    assert_equal 2, call_count
  end

  test "raises ThreadAgent::SlackError after max rate limit retries" do
    handler = ThreadAgent::Slack::RetryHandler.new(max_retries: 2)

    rate_limit_error = ::Slack::Web::Api::Errors::RateLimited.new("Rate limited")
    rate_limit_error.stubs(:response_metadata).returns({ "retry_after" => 1 })

    call_count = 0
    test_block = -> {
      call_count += 1
      raise rate_limit_error
    }

    handler.expects(:sleep).with(1).twice

    assert_raises(ThreadAgent::SlackError, /Rate limit exceeded after 2 retries/) do
      handler.with_retries { test_block.call }
    end
    assert_equal 3, call_count # Initial + 2 retries
  end

  test "retries timeout errors with exponential backoff" do
    handler = ThreadAgent::Slack::RetryHandler.new

    timeout_error = ::Slack::Web::Api::Errors::TimeoutError.new("Timeout")

    call_count = 0
    test_block = -> {
      call_count += 1
      raise timeout_error if call_count <= 2
      "success"
    }

    # Initial delay: 1.0, second delay: 2.0 (doubled)
    handler.expects(:sleep).with(1.0).once
    handler.expects(:sleep).with(2.0).once

    result = handler.with_retries { test_block.call }
    assert_equal "success", result
    assert_equal 3, call_count
  end

  test "retries server errors (5xx) but not client errors (4xx)" do
    handler = ThreadAgent::Slack::RetryHandler.new

    server_error = ::Slack::Web::Api::Errors::SlackError.new("Server error")
    server_error.stubs(:response_metadata).returns({ "status_code" => 503 })

    client_error = ::Slack::Web::Api::Errors::SlackError.new("Client error")
    client_error.stubs(:response_metadata).returns({ "status_code" => 404 })

    # Test server error retry
    call_count = 0
    test_block = -> {
      call_count += 1
      raise server_error if call_count == 1
      "success"
    }

    handler.expects(:sleep).with(1.0).once

    result = handler.with_retries { test_block.call }
    assert_equal "success", result
    assert_equal 2, call_count

    # Test client error no retry
    call_count = 0
    test_block = -> {
      call_count += 1
      raise client_error
    }

    handler.expects(:sleep).never

    assert_raises(ThreadAgent::SlackError, /Slack API client error \(404\)/) do
      handler.with_retries { test_block.call }
    end
    assert_equal 1, call_count # No retries
  end

  test "retries network timeout errors" do
    handler = ThreadAgent::Slack::RetryHandler.new

    network_error = Net::ReadTimeout.new("Network timeout")

    call_count = 0
    test_block = -> {
      call_count += 1
      raise network_error if call_count <= 2
      "success"
    }

    handler.expects(:sleep).with(1.0).once
    handler.expects(:sleep).with(2.0).once

    result = handler.with_retries { test_block.call }
    assert_equal "success", result
    assert_equal 3, call_count
  end

  test "caps exponential backoff at max delay" do
    handler = ThreadAgent::Slack::RetryHandler.new

    timeout_error = ::Slack::Web::Api::Errors::TimeoutError.new("Timeout")

    call_count = 0
    test_block = -> {
      call_count += 1
      raise timeout_error if call_count <= 3
      "success"
    }

    # With max_delay of 3.0, delays should be: 1.0, 2.0, 3.0 (capped)
    handler.expects(:sleep).with(1.0).once
    handler.expects(:sleep).with(2.0).once
    handler.expects(:sleep).with(3.0).once

    result = handler.with_retries(max_delay: 3.0) { test_block.call }
    assert_equal "success", result
    assert_equal 4, call_count
  end
end
