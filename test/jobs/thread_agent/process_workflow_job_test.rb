# frozen_string_literal: true

require "test_helper"

class ThreadAgent::ProcessWorkflowJobTest < ActiveJob::TestCase
  def setup
    @valid_payload = {
      workflow_run_id: 1,
      thread_data: {
        messages: [
          { text: "Hello", user: "U123" }
        ]
      }
    }
  end

  test "returns early with nil payload" do
    result = nil

    assert_no_enqueued_jobs do
      result = ThreadAgent::ProcessWorkflowJob.new.perform(nil)
    end

    assert result
  end

  test "returns early with non-hash payload" do
    result = nil

    assert_no_enqueued_jobs do
      result = ThreadAgent::ProcessWorkflowJob.new.perform("not a hash")
    end

    assert result
  end

  test "returns early when workflow_run_id is missing" do
    payload = { thread_data: {} }
    result = nil

    assert_no_enqueued_jobs do
      result = ThreadAgent::ProcessWorkflowJob.new.perform(payload)
    end

    assert result
  end

  test "returns early when workflow_run_id is blank" do
    payload = { workflow_run_id: "", thread_data: {} }
    result = nil

    assert_no_enqueued_jobs do
      result = ThreadAgent::ProcessWorkflowJob.new.perform(payload)
    end

    assert result
  end
end
