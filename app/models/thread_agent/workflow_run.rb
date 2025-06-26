# frozen_string_literal: true

module ThreadAgent
  class WorkflowRun < ApplicationRecord
    self.table_name = "thread_agent_workflow_runs"

    belongs_to :template, optional: true

    serialize :output_data, coder: JSON
    serialize :input_data, coder: JSON

    enum :status, {
      pending: "pending",
      running: "running",
      completed: "completed",
      failed: "failed",
      cancelled: "cancelled"
    }

    validates :status, presence: true
    validates :workflow_name, presence: true, length: { minimum: 1, maximum: 255 }
    validates :error_message, length: { maximum: 2000 }, allow_nil: true
    validates :slack_message_id, length: { maximum: 255 }, allow_blank: true
    validates :slack_channel_id, length: { maximum: 255 }, allow_blank: true
    validates :slack_thread_ts, length: { maximum: 255 }, allow_blank: true

    validates :error_message, presence: true, if: :failed?
    validates :finished_at, comparison: { greater_than: :started_at }, if: -> { started_at.present? && finished_at.present? }

    scope :active, -> { where(status: %w[pending running]) }
    scope :by_workflow, ->(name) { where(workflow_name: name) }
    scope :by_slack_channel, ->(channel_id) { where(slack_channel_id: channel_id) }
    scope :by_slack_message, ->(message_id) { where(slack_message_id: message_id) }
    scope :by_slack_thread, ->(thread_ts) { where(slack_thread_ts: thread_ts) }

    def duration
      return nil unless started_at && finished_at
      finished_at - started_at
    end

    def active?
      pending? || running?
    end

    def finished?
      completed? || failed? || cancelled?
    end

    def mark_started!
      update!(status: :running, started_at: Time.current)
    end

    def mark_completed!(output_data = nil)
      update!(
        status: :completed,
        finished_at: Time.current,
        output_data: output_data
      )
    end

    def mark_failed!(error_msg)
      update!(
        status: :failed,
        finished_at: Time.current,
        error_message: error_msg
      )
    end

    def mark_cancelled!
      update!(status: :cancelled, finished_at: Time.current)
    end

    def current_step
      return nil if steps.blank?
      steps.last
    end

    def add_step(step_name, data: nil)
      self.steps ||= []
      steps << {
        "name" => step_name.to_s,
        "completed_at" => Time.current.iso8601,
        "data" => data
      }.compact
      save!
    end

    def fail_step(step_name, error)
      self.steps ||= []
      steps << {
        "name" => step_name.to_s,
        "failed_at" => Time.current.iso8601,
        "error" => error
      }
      save!
    end

    def self.create_for_workflow(workflow_name, slack_message_id: nil, slack_channel_id: nil, slack_thread_ts: nil, input_data: nil, template: nil)
      create!(
        workflow_name: workflow_name,
        status: :pending,
        slack_message_id: slack_message_id,
        slack_channel_id: slack_channel_id,
        slack_thread_ts: slack_thread_ts,
        input_data: input_data,
        template: template,
        steps: []
      )
    end
  end
end
