# frozen_string_literal: true

require "test_helper"

module ThreadAgent
  class RetryHandlerTest < ActiveSupport::TestCase
    class TestError < ThreadAgent::Error; end
    class NonRetryableError < StandardError; end

    def setup
      @handler = RetryHandler.new
      @test_error = TestError.new("Test error message")
      @non_retryable_error = NonRetryableError.new("Non-retryable error")
    end

    test "initializes with default configuration" do
      handler = RetryHandler.new

      assert_equal 3, handler.max_attempts
      assert_equal 1.0, handler.base_interval
      assert_equal 2.0, handler.backoff_factor
      assert_equal 30.0, handler.max_interval
      assert_equal true, handler.jitter
      expected_errors = [ ThreadAgent::Error ] + ThreadAgent::RetryHandler::GENERIC_RETRYABLE_ERRORS
      assert_equal expected_errors, handler.retryable_errors
    end

    test "initializes with custom configuration" do
      handler = RetryHandler.new(
        max_attempts: 5,
        base_interval: 2.0,
        backoff_factor: 1.5,
        max_interval: 60.0,
        jitter: false,
        retryable_errors: [ TestError ],
        final_error_class: TestError
      )

      assert_equal 5, handler.max_attempts
      assert_equal 2.0, handler.base_interval
      assert_equal 1.5, handler.backoff_factor
      assert_equal 60.0, handler.max_interval
      assert_equal false, handler.jitter
      assert_equal [ TestError ], handler.retryable_errors
    end

    test "successfully executes block without retries when no error occurs" do
      result = @handler.retry_with { "success" }
      assert_equal "success", result
    end

    test "retries on retryable error and eventually succeeds" do
      call_count = 0

      result = @handler.retry_with do
        call_count += 1
        raise @test_error if call_count < 3
        "success after retries"
      end

      assert_equal "success after retries", result
      assert_equal 3, call_count
    end

        test "exhausts retries and raises final error" do
      call_count = 0

      error = assert_raises(ThreadAgent::Error) do
        @handler.retry_with do
          call_count += 1
          raise @test_error
        end
      end

      assert_equal 4, call_count  # Initial attempt + 3 retries
      assert_includes error.message, "Operation failed after 3 retries"
      assert_includes error.message, "Test error message"
    end

    test "does not retry non-retryable errors" do
      call_count = 0

      error = assert_raises(ThreadAgent::Error) do
        @handler.retry_with do
          call_count += 1
          raise @non_retryable_error
        end
      end

      assert_equal 1, call_count
      assert_includes error.message, "Operation failed after 0 retries"
    end

        test "respects per-call max_attempts override" do
      call_count = 0

      error = assert_raises(ThreadAgent::Error) do
        @handler.retry_with(max_attempts: 1) do
          call_count += 1
          raise @test_error
        end
      end

      assert_equal 2, call_count  # Initial attempt + 1 retry
      assert_includes error.message, "Operation failed after 1 retries"
    end

    test "respects per-call retryable_errors override" do
      call_count = 0

      error = assert_raises(ThreadAgent::Error) do
        @handler.retry_with(retryable_errors: [ NonRetryableError ]) do
          call_count += 1
          raise @test_error  # This should not be retried with the override
        end
      end

      assert_equal 1, call_count
      assert_includes error.message, "Operation failed after 0 retries"
    end

    test "non_retryable_errors take precedence over retryable_errors" do
      handler = RetryHandler.new(
        retryable_errors: [ TestError, NonRetryableError ],
        non_retryable_errors: [ NonRetryableError ]
      )

      call_count = 0

      error = assert_raises(ThreadAgent::Error) do
        handler.retry_with do
          call_count += 1
          raise @non_retryable_error  # Should not retry despite being in retryable_errors
        end
      end

      assert_equal 1, call_count
      assert_includes error.message, "Operation failed after 0 retries"
    end

    test "calculates exponential backoff intervals correctly" do
      handler = RetryHandler.new(
        base_interval: 1.0,
        backoff_factor: 2.0,
        max_interval: 10.0,
        jitter: false
      )

      # Access private method for testing
      intervals = []
      (1..4).each do |attempt|
        interval = handler.send(:calculate_interval, attempt, 1.0, 10.0, false)
        intervals << interval
      end

      assert_equal [ 1.0, 2.0, 4.0, 8.0 ], intervals
    end

    test "caps intervals at max_interval" do
      handler = RetryHandler.new(jitter: false)

      interval = handler.send(:calculate_interval, 10, 1.0, 5.0, false)
      assert_equal 5.0, interval
    end

        test "applies jitter when enabled" do
      handler = RetryHandler.new(jitter: true)

      # Generate multiple intervals to test jitter variation
      intervals = []
      10.times do
        interval = handler.send(:calculate_interval, 1, 2.0, 10.0, true)
        intervals << interval
      end

      # All intervals should be around 2.0 ± 25% (1.5 to 2.5)
      intervals.each do |interval|
        assert interval >= 1.5, "Interval #{interval} should be >= 1.5"
        assert interval <= 2.5, "Interval #{interval} should be <= 2.5"
      end

      # Check that there's actually variation (not all the same)
      assert intervals.uniq.length > 1, "Expected variation in jittered intervals"
    end

        test "logs retry attempts with context" do
      call_count = 0

      Rails.logger.expects(:warn).times(3).with do |message|
        message.include?("[test-context]") &&
        message.include?("Retry attempt") &&
        message.include?("TestError")
      end

      Rails.logger.expects(:error).once.with do |message|
        message.include?("[test-context]") &&
        message.include?("Operation failed after 3 retries")
      end

      assert_raises(ThreadAgent::Error) do
        @handler.retry_with(context: "test-context") do
          call_count += 1
          raise @test_error
        end
      end
    end

        test "logs retry attempts without context" do
      call_count = 0

      Rails.logger.expects(:warn).times(3).with do |message|
        !message.include?("[") &&
        message.include?("Retry attempt") &&
        message.include?("TestError")
      end

      Rails.logger.expects(:error).once.with do |message|
        !message.include?("[") &&
        message.include?("Operation failed after 3 retries")
      end

      assert_raises(ThreadAgent::Error) do
        @handler.retry_with do
          call_count += 1
          raise @test_error
        end
      end
    end

    test "calls before_retry hook when defined" do
      handler = Class.new(RetryHandler) do
        attr_reader :before_retry_calls

        def initialize(*args, **kwargs)
          super
          @before_retry_calls = []
        end

        private

        def before_retry(attempt_count)
          @before_retry_calls << attempt_count
        end
      end.new

      call_count = 0

      result = handler.retry_with do
        call_count += 1
        raise TestError.new("test") if call_count < 3
        "success"
      end

      assert_equal "success", result
      assert_equal [ 0, 1, 2 ], handler.before_retry_calls
    end

    test "calls after_retry hook when defined" do
      handler = Class.new(RetryHandler) do
        attr_reader :after_retry_calls

        def initialize(*args, **kwargs)
          super
          @after_retry_calls = []
        end

        private

        def after_retry(attempt_count)
          @after_retry_calls << attempt_count
        end
      end.new

      call_count = 0

      result = handler.retry_with do
        call_count += 1
        raise TestError.new("test") if call_count < 3
        "success"
      end

      assert_equal "success", result
      assert_equal [ 2 ], handler.after_retry_calls
    end

    test "uses custom final_error_class" do
      handler = RetryHandler.new(final_error_class: TestError)

      error = assert_raises(TestError) do
        handler.retry_with do
          raise ThreadAgent::Error.new("original error")
        end
      end

      assert_includes error.message, "Operation failed after 3 retries"
    end

    test "preserves original error message in final error" do
      original_message = "Very specific error message"

      error = assert_raises(ThreadAgent::Error) do
        @handler.retry_with do
          raise TestError.new(original_message)
        end
      end

      assert_includes error.message, original_message
    end

    test "handles zero max_attempts gracefully" do
      call_count = 0

      error = assert_raises(ThreadAgent::Error) do
        @handler.retry_with(max_attempts: 0) do
          call_count += 1
          raise @test_error
        end
      end

      assert_equal 1, call_count
      assert_includes error.message, "Operation failed after 0 retries"
    end
  end
end
