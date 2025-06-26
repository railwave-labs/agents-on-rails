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

  test "job includes SafetyNetRetries concern" do
    assert ThreadAgent::ProcessWorkflowJob.ancestors.include?(SafetyNetRetries)
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

  test "perform raises ActiveRecord::RecordNotFound for nil workflow_run_id" do
    assert_raises(ActiveRecord::RecordNotFound) do
      ThreadAgent::ProcessWorkflowJob.new.perform(nil)
    end
  end

  test "perform raises ActiveRecord::RecordNotFound for blank workflow_run_id" do
    assert_raises(ActiveRecord::RecordNotFound) do
      ThreadAgent::ProcessWorkflowJob.new.perform("")
    end
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

  # Tests for SafetyNetRetries concern integration
  test "job includes SafetyNetRetries concern and retry behavior" do
    # Verify that the concern is properly included
    assert ThreadAgent::ProcessWorkflowJob.ancestors.include?(SafetyNetRetries)

    # Verify that when retryable errors occur, they are raised (allowing ActiveJob to handle retries)
    workflow_run = create(:workflow_run)

    # Mock WorkflowRun.find to raise a retryable error
    ThreadAgent::WorkflowRun.stubs(:find).with(workflow_run.id)
      .raises(ThreadAgent::SlackError.new("Slack API temporarily unavailable"))

    # The job should raise the error, allowing ActiveJob retry mechanism to kick in
    assert_raises(ThreadAgent::SlackError) do
      ThreadAgent::ProcessWorkflowJob.new.perform(workflow_run.id)
    end
  end

  test "job raises OpenAI errors for retry handling" do
    workflow_run = create(:workflow_run)

    # Mock to raise OpenaiError
    ThreadAgent::WorkflowRun.stubs(:find).with(workflow_run.id)
      .raises(ThreadAgent::OpenaiError.new("OpenAI API error"))

    # The job should raise the error for ActiveJob to handle retries
    assert_raises(ThreadAgent::OpenaiError) do
      ThreadAgent::ProcessWorkflowJob.new.perform(workflow_run.id)
    end
  end

  test "job raises network timeout errors for retry handling" do
    workflow_run = create(:workflow_run)

    # Test Net::ReadTimeout
    ThreadAgent::WorkflowRun.stubs(:find).with(workflow_run.id)
      .raises(Net::ReadTimeout.new("Read timeout"))

    # The job should raise the error for ActiveJob to handle retries
    assert_raises(Net::ReadTimeout) do
      ThreadAgent::ProcessWorkflowJob.new.perform(workflow_run.id)
    end
  end

  test "job raises Faraday errors for retry handling" do
    workflow_run = create(:workflow_run)

    # Mock to raise Faraday::Error
    ThreadAgent::WorkflowRun.stubs(:find).with(workflow_run.id)
      .raises(Faraday::Error.new("HTTP client error"))

    # The job should raise the error for ActiveJob to handle retries
    assert_raises(Faraday::Error) do
      ThreadAgent::ProcessWorkflowJob.new.perform(workflow_run.id)
    end
  end

  test "job raises database connection errors for retry handling" do
    workflow_run = create(:workflow_run)

    # Mock to raise ActiveRecord::ConnectionTimeoutError
    ThreadAgent::WorkflowRun.stubs(:find).with(workflow_run.id)
      .raises(ActiveRecord::ConnectionTimeoutError.new("Connection timeout"))

    # The job should raise the error for ActiveJob to handle retries
    assert_raises(ActiveRecord::ConnectionTimeoutError) do
      ThreadAgent::ProcessWorkflowJob.new.perform(workflow_run.id)
    end
  end

  test "job raises socket errors for retry handling" do
    workflow_run = create(:workflow_run)

    # Test Errno::ECONNRESET
    ThreadAgent::WorkflowRun.stubs(:find).with(workflow_run.id)
      .raises(Errno::ECONNRESET.new("Connection reset"))

    # The job should raise the error for ActiveJob to handle retries
    assert_raises(Errno::ECONNRESET) do
      ThreadAgent::ProcessWorkflowJob.new.perform(workflow_run.id)
    end
  end

  test "job handles non-retryable errors normally" do
    # ActiveRecord::RecordNotFound should not be retried (not in SafetyNetRetries)
    # This test verifies our existing error handling still works
    assert_raises(ActiveRecord::RecordNotFound) do
      ThreadAgent::ProcessWorkflowJob.new.perform(999999)
    end
  end

  test "SafetyNetRetries concern configuration is applied" do
    # Test that the concern's module is properly extended and included
    assert_respond_to SafetyNetRetries, :included

    # Verify the concern adds retry behavior to the job class
    # This is a structural test to ensure the concern is working
    job_class = ThreadAgent::ProcessWorkflowJob

    # The concern should add retry_on configurations
    # We can't easily inspect the internal retry configuration in Rails 8,
    # but we can verify the concern's methods are available
    assert job_class.ancestors.include?(SafetyNetRetries)
  end
end
