class AddTemplateToWorkflowRuns < ActiveRecord::Migration[8.0]
  def change
    add_reference :thread_agent_workflow_runs, :template, null: true, foreign_key: { to_table: :thread_agent_templates }
  end
end
