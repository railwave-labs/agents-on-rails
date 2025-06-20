class AddSlackFieldsToThreadAgentWorkflowRuns < ActiveRecord::Migration[8.0]
  def change
    add_column :thread_agent_workflow_runs, :slack_message_id, :string, limit: 255
    add_column :thread_agent_workflow_runs, :slack_channel_id, :string, limit: 255

    add_index :thread_agent_workflow_runs, [ :slack_channel_id, :slack_message_id ]
  end
end
