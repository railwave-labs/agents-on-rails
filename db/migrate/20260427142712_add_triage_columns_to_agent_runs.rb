class AddTriageColumnsToAgentRuns < ActiveRecord::Migration[8.0]
  def change
    add_column :agent_runs, :kind,        :string,  default: "thread_capture", null: false
    add_column :agent_runs, :cost_cents,  :integer
    add_column :agent_runs, :token_usage, :json
    add_index  :agent_runs, :kind
  end
end
