# frozen_string_literal: true

require "test_helper"

class ThreadAgent::Openai::RetryHandlerTest < ActiveSupport::TestCase
  test "initializes with default max attempts" do
    handler = ThreadAgent::Openai::RetryHandler.new
    assert_equal 3, handler.max_attempts
  end

  test "initializes with custom max attempts" do
    handler = ThreadAgent::Openai::RetryHandler.new(max_attempts: 5)
    assert_equal 5, handler.max_attempts
  end

  test "executes block successfully without retries" do
    handler = ThreadAgent::Openai::RetryHandler.new
    result = handler.retry_with { "success" }
    assert_equal "success", result
  end

  test "retries on OpenAI::Error" do
    handler = ThreadAgent::Openai::RetryHandler.new(max_attempts: 2)
    call_count = 0

    error = assert_raises(ThreadAgent::OpenaiError) do
      handler.retry_with do
        call_count += 1
        raise OpenAI::Error.new("OpenAI error")
      end
    end

    assert_equal 3, call_count  # 1 initial + 2 retries
    assert_includes error.message, "Operation failed after 2 retries"
  end

  test "retries on Faraday::Error" do
    handler = ThreadAgent::Openai::RetryHandler.new(max_attempts: 2)
    call_count = 0

    error = assert_raises(ThreadAgent::OpenaiError) do
      handler.retry_with do
        call_count += 1
        raise Faraday::Error.new("HTTP error")
      end
    end

    assert_equal 3, call_count  # 1 initial + 2 retries
    assert_includes error.message, "Operation failed after 2 retries"
  end

  test "retries on network timeout errors" do
    handler = ThreadAgent::Openai::RetryHandler.new(max_attempts: 2)
    call_count = 0

    error = assert_raises(ThreadAgent::OpenaiError) do
      handler.retry_with do
        call_count += 1
        raise Net::ReadTimeout.new("Network timeout")
      end
    end

    assert_equal 3, call_count  # 1 initial + 2 retries
    assert_includes error.message, "Operation failed after 2 retries"
  end

  test "does not retry on OpenAI::AuthenticationError" do
    handler = ThreadAgent::Openai::RetryHandler.new(max_attempts: 2)
    call_count = 0

    error = assert_raises(ThreadAgent::OpenaiError) do
      handler.retry_with do
        call_count += 1
        raise OpenAI::AuthenticationError.new("Invalid API key")
      end
    end

    assert_equal 1, call_count  # No retries
    assert_includes error.message, "Operation failed after 0 retries"
  end

  test "does not retry on OpenAI::ConfigurationError" do
    handler = ThreadAgent::Openai::RetryHandler.new(max_attempts: 2)
    call_count = 0

    error = assert_raises(ThreadAgent::OpenaiError) do
      handler.retry_with do
        call_count += 1
        raise OpenAI::ConfigurationError.new("Invalid configuration")
      end
    end

    assert_equal 1, call_count  # No retries
    assert_includes error.message, "Operation failed after 0 retries"
  end

  test "exhausts retries and raises ThreadAgent::OpenaiError" do
    handler = ThreadAgent::Openai::RetryHandler.new(max_attempts: 3)
    call_count = 0

    error = assert_raises(ThreadAgent::OpenaiError) do
      handler.retry_with do
        call_count += 1
        raise OpenAI::Error.new("Persistent error")
      end
    end

    assert_equal 4, call_count  # 1 initial + 3 retries
    assert_includes error.message, "Operation failed after 3 retries"
    assert_includes error.message, "Persistent error"
  end

  test "respects exponential backoff timing without jitter" do
    handler = ThreadAgent::Openai::RetryHandler.new(max_attempts: 3, jitter: false)
    call_count = 0
    sleep_times = []

    # Mock sleep to capture the intervals
    handler.define_singleton_method(:sleep) do |interval|
      sleep_times << interval
    end

    error = assert_raises(ThreadAgent::OpenaiError) do
      handler.retry_with do
        call_count += 1
        raise OpenAI::Error.new("Retryable error")
      end
    end

    assert_equal 4, call_count  # 1 initial + 3 retries
    assert_equal [ 1.0, 2.0, 4.0 ], sleep_times  # Exponential backoff: 1s, 2s, 4s
  end
end
