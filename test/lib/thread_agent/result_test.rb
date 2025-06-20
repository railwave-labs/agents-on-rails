# frozen_string_literal: true

require "test_helper"

class ThreadAgent::ResultTest < ActiveSupport::TestCase
  test "creates successful result with data" do
    result = ThreadAgent::Result.success({ message: "test" })

    assert result.success?
    assert_not result.failure?
    assert_equal({ message: "test" }, result.data)
    assert_nil result.error
    assert_equal({}, result.metadata)
  end

  test "creates successful result with metadata" do
    result = ThreadAgent::Result.success({ data: "test" }, { info: "extra" })

    assert result.success?
    assert_equal({ info: "extra" }, result.metadata)
  end

  test "creates failure result with error" do
    result = ThreadAgent::Result.failure("Something went wrong")

    assert result.failure?
    assert_not result.success?
    assert_nil result.data
    assert_equal "Something went wrong", result.error
    assert_equal({}, result.metadata)
  end

  test "creates failure result with metadata" do
    result = ThreadAgent::Result.failure("Error occurred", { retry_after: 30 })

    assert result.failure?
    assert_equal "Error occurred", result.error
    assert_equal({ retry_after: 30 }, result.metadata)
  end

  test "initializes with custom values" do
    result = ThreadAgent::Result.new(true, "data", "error", { key: "value" })

    assert result.success?
    assert_equal "data", result.data
    assert_equal "error", result.error
    assert_equal({ key: "value" }, result.metadata)
  end
end
