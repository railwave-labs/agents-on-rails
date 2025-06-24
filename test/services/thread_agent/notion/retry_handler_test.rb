# frozen_string_literal: true

require "test_helper"

class ThreadAgent::Notion::RetryHandlerTest < ActiveSupport::TestCase
  test "initializes with default max attempts" do
    handler = ThreadAgent::Notion::RetryHandler.new
    assert_equal 3, handler.max_attempts
  end

  test "initializes with custom max attempts" do
    handler = ThreadAgent::Notion::RetryHandler.new(max_attempts: 5)
    assert_equal 5, handler.max_attempts
  end

  test "executes block successfully without retries" do
    handler = ThreadAgent::Notion::RetryHandler.new
    result = handler.retry_with { "success" }
    assert_equal "success", result
  end

  test "retries on Notion::Api::Errors::TimeoutError" do
    handler = ThreadAgent::Notion::RetryHandler.new(max_attempts: 2)
    call_count = 0

    error = assert_raises(ThreadAgent::NotionError) do
      handler.retry_with do
        call_count += 1
        raise ::Notion::Api::Errors::TimeoutError.new("Notion API timeout", 408)
      end
    end

    assert_equal 3, call_count  # 1 initial + 2 retries
    assert_includes error.message, "Operation failed after 2 retries"
  end

  test "retries on Faraday::Error" do
    handler = ThreadAgent::Notion::RetryHandler.new(max_attempts: 2)
    call_count = 0

    error = assert_raises(ThreadAgent::NotionError) do
      handler.retry_with do
        call_count += 1
        raise Faraday::Error.new("HTTP error")
      end
    end

    assert_equal 3, call_count  # 1 initial + 2 retries
    assert_includes error.message, "Operation failed after 2 retries"
  end

  test "retries on network timeout errors" do
    handler = ThreadAgent::Notion::RetryHandler.new(max_attempts: 2)
    call_count = 0

    error = assert_raises(ThreadAgent::NotionError) do
      handler.retry_with do
        call_count += 1
        raise Net::ReadTimeout.new("Network timeout")
      end
    end

    assert_equal 3, call_count  # 1 initial + 2 retries
    assert_includes error.message, "Operation failed after 2 retries"
  end

  test "does not retry on Notion::Api::Errors::Unauthorized" do
    handler = ThreadAgent::Notion::RetryHandler.new(max_attempts: 2)
    call_count = 0

    error = assert_raises(ThreadAgent::NotionError) do
      handler.retry_with do
        call_count += 1
        raise ::Notion::Api::Errors::Unauthorized.new("Invalid API key", 401)
      end
    end

    assert_equal 1, call_count  # No retries
    assert_includes error.message, "Operation failed after 0 retries"
  end

  test "exhausts retries and raises ThreadAgent::NotionError" do
    handler = ThreadAgent::Notion::RetryHandler.new(max_attempts: 3)
    call_count = 0

    error = assert_raises(ThreadAgent::NotionError) do
      handler.retry_with do
        call_count += 1
        raise ::Notion::Api::Errors::TimeoutError.new("Persistent error", 408)
      end
    end

    assert_equal 4, call_count  # 1 initial + 3 retries
    assert_includes error.message, "Operation failed after 3 retries"
    assert_includes error.message, "Persistent error"
  end

  test "respects exponential backoff timing without jitter" do
    handler = ThreadAgent::Notion::RetryHandler.new(max_attempts: 3, jitter: false)
    call_count = 0
    sleep_times = []

    # Mock sleep to capture the intervals
    handler.define_singleton_method(:sleep) do |interval|
      sleep_times << interval
    end

    error = assert_raises(ThreadAgent::NotionError) do
      handler.retry_with do
        call_count += 1
        raise ::Notion::Api::Errors::TimeoutError.new("Retryable error", 408)
      end
    end

    assert_equal 4, call_count  # 1 initial + 3 retries
    assert_equal [ 1.0, 2.0, 4.0 ], sleep_times  # Exponential backoff: 1s, 2s, 4s
  end

  test "retries notion-specific internal errors" do
    handler = ThreadAgent::Notion::RetryHandler.new(max_attempts: 2)
    call_count = 0

    error = assert_raises(ThreadAgent::NotionError) do
      handler.retry_with do
        call_count += 1
        raise ::Notion::Api::Errors::InternalError.new("Internal server error", 500)
      end
    end

    assert_equal 3, call_count
    assert_includes error.message, "Operation failed after 2 retries"
  end

  test "does not retry notion forbidden errors" do
    handler = ThreadAgent::Notion::RetryHandler.new(max_attempts: 3)
    call_count = 0

    error = assert_raises(ThreadAgent::NotionError) do
      handler.retry_with do
        call_count += 1
        raise ::Notion::Api::Errors::Forbidden.new("Forbidden", 403)
      end
    end

    assert_equal 1, call_count  # No retries
    assert_includes error.message, "Operation failed after 0 retries"
  end

  test "handles notion error successfully after retries" do
    handler = ThreadAgent::Notion::RetryHandler.new(max_attempts: 3, base_interval: 0.001)
    call_count = 0

    result = handler.retry_with do
      call_count += 1
      raise ::Notion::Api::Errors::TimeoutError.new("Timeout", 408) if call_count < 2
      "success"
    end

    assert_equal "success", result
    assert_equal 2, call_count
  end
end
