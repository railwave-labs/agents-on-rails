class ModifyThreadAgentWorkflowRunsRemoveAgentTypeAddSteps < ActiveRecord::Migration[7.1]
  def change
    # Remove agent_type column and its indexes
    remove_index :thread_agent_workflow_runs, name: "index_thread_agent_workflow_runs_on_agent_type_and_status"
    remove_index :thread_agent_workflow_runs, name: "index_thread_agent_workflow_runs_on_agent_type"
    remove_column :thread_agent_workflow_runs, :agent_type, :string

    # Add steps column for tracking workflow progress
    add_column :thread_agent_workflow_runs, :steps, :json, default: []

    # Add new indexes for workflow-based queries
    add_index :thread_agent_workflow_runs, [ :workflow_name, :status ]
  end
end
