# frozen_string_literal: true

require "test_helper"

class ThreadAgent::Slack::RetryHandlerTest < ActiveSupport::TestCase
  def setup
    @handler = ThreadAgent::Slack::RetryHandler.new
  end

  test "initializes with default max attempts" do
    assert_equal 3, @handler.max_attempts
  end

  test "initializes with custom max attempts" do
    handler = ThreadAgent::Slack::RetryHandler.new(max_attempts: 5)
    assert_equal 5, handler.max_attempts
  end

  test "executes block successfully without retries" do
    result = @handler.retry_with { "success" }
    assert_equal "success", result
  end

  test "retries on Slack rate limited error and respects retry_after header" do
    call_count = 0
    retry_after_value = 2.5
    sleep_times = []

    # Create a mock rate limited error with retry_after in response_metadata
    rate_limited_error = ::Slack::Web::Api::Errors::RateLimited.new("Rate limited")
    rate_limited_error.define_singleton_method(:response_metadata) do
      { "retry_after" => retry_after_value }
    end

    # Mock sleep to capture the intervals
    @handler.define_singleton_method(:sleep) do |interval|
      sleep_times << interval
    end

    error = assert_raises(ThreadAgent::SlackError) do
      @handler.retry_with(max_attempts: 2) do
        call_count += 1
        raise rate_limited_error
      end
    end

    assert_equal 3, call_count  # 1 initial + 2 retries
    assert_equal [ retry_after_value, retry_after_value ], sleep_times  # Two retries, both using retry_after
    assert_includes error.message, "Operation failed after 2 retries"
  end

  test "falls back to exponential backoff when no retry_after header" do
    call_count = 0
    sleep_times = []

    # Create a rate limited error without retry_after
    rate_limited_error = ::Slack::Web::Api::Errors::RateLimited.new("Rate limited")
    rate_limited_error.define_singleton_method(:response_metadata) { {} }

    # Mock sleep to capture the intervals
    @handler.define_singleton_method(:sleep) do |interval|
      sleep_times << interval
    end

    error = assert_raises(ThreadAgent::SlackError) do
      @handler.retry_with(max_attempts: 2) do
        call_count += 1
        raise rate_limited_error
      end
    end

    assert_equal 3, call_count  # 1 initial + 2 retries
    assert_equal [ 1.0, 2.0 ], sleep_times  # Exponential backoff: 1.0s, 2.0s
    assert_includes error.message, "Operation failed after 2 retries"
  end

  test "retries on Slack timeout errors" do
    call_count = 0

    error = assert_raises(ThreadAgent::SlackError) do
      @handler.retry_with(max_attempts: 2) do
        call_count += 1
        raise ::Slack::Web::Api::Errors::TimeoutError.new("Timeout")
      end
    end

    assert_equal 3, call_count  # 1 initial + 2 retries
    assert_includes error.message, "Operation failed after 2 retries"
  end

  test "retries on generic Slack errors" do
    call_count = 0

    error = assert_raises(ThreadAgent::SlackError) do
      @handler.retry_with(max_attempts: 2) do
        call_count += 1
        raise ::Slack::Web::Api::Errors::SlackError.new("Generic slack error")
      end
    end

    assert_equal 3, call_count  # 1 initial + 2 retries
    assert_includes error.message, "Operation failed after 2 retries"
  end

  test "retries on generic network errors" do
    call_count = 0

    error = assert_raises(ThreadAgent::SlackError) do
      @handler.retry_with(max_attempts: 2) do
        call_count += 1
        raise Net::ReadTimeout.new("Read timeout")
      end
    end

    assert_equal 3, call_count  # 1 initial + 2 retries
    assert_includes error.message, "Operation failed after 2 retries"
  end
end
