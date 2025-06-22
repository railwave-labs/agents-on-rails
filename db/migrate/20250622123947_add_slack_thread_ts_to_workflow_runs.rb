class AddSlackThreadTsToWorkflowRuns < ActiveRecord::Migration[8.0]
  def change
    add_column :thread_agent_workflow_runs, :slack_thread_ts, :string, limit: 255

    # Add index for efficient lookups by thread
    add_index :thread_agent_workflow_runs, [ :slack_channel_id, :slack_thread_ts ]
  end
end
