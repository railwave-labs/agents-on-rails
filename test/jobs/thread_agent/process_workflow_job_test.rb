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

  test "job class exists and inherits from ApplicationJob" do
    assert ThreadAgent::ProcessWorkflowJob.ancestors.include?(ApplicationJob)
    assert ThreadAgent::ProcessWorkflowJob.ancestors.include?(ActiveJob::Base)
  end

  test "job can be enqueued with workflow_run_id" do
    workflow_run = create(:workflow_run)

    assert_enqueued_with(job: ThreadAgent::ProcessWorkflowJob, args: [ workflow_run.id ]) do
      ThreadAgent::ProcessWorkflowJob.perform_later(workflow_run.id)
    end
  end

  test "perform method accepts workflow_run_id parameter" do
    workflow_run = create(:workflow_run)

    # Should not raise any errors
    assert_nothing_raised do
      ThreadAgent::ProcessWorkflowJob.new.perform(workflow_run.id)
    end
  end

  test "perform raises ArgumentError when workflow_run_id is nil" do
    error = assert_raises(ArgumentError) do
      ThreadAgent::ProcessWorkflowJob.new.perform(nil)
    end

    assert_equal "workflow_run_id cannot be nil or blank", error.message
  end

  test "perform raises ArgumentError when workflow_run_id is blank" do
    error = assert_raises(ArgumentError) do
      ThreadAgent::ProcessWorkflowJob.new.perform("")
    end

    assert_equal "workflow_run_id cannot be nil or blank", error.message
  end

  test "perform raises ActiveRecord::RecordNotFound for invalid workflow_run_id" do
    assert_raises(ActiveRecord::RecordNotFound) do
      ThreadAgent::ProcessWorkflowJob.new.perform(999999)
    end
  end

  test "perform logs appropriate messages for valid workflow_run_id" do
    workflow_run = create(:workflow_run)

    Rails.logger.expects(:info).with("ProcessWorkflowJob started for workflow_run_id: #{workflow_run.id}")
    Rails.logger.expects(:info).with("Processing workflow_run: #{workflow_run.id}")
    Rails.logger.expects(:info).with("ProcessWorkflowJob completed for workflow_run_id: #{workflow_run.id}")

    ThreadAgent::ProcessWorkflowJob.new.perform(workflow_run.id)
  end
end
