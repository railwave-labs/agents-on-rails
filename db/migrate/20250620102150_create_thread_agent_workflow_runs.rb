class CreateThreadAgentWorkflowRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :thread_agent_workflow_runs do |t|
      t.string :workflow_name, null: false
      t.string :status, null: false, default: "pending"
      t.text :input_data
      t.text :output_data
      t.text :error_message
      t.json :steps, default: []
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps null: false
    end

    # Indexes for performance
    add_index :thread_agent_workflow_runs, [ :workflow_name, :status ]
    add_index :thread_agent_workflow_runs, :status
    add_index :thread_agent_workflow_runs, :started_at
  end
end
