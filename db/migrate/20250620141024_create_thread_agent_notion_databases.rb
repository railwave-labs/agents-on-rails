class CreateThreadAgentNotionDatabases < ActiveRecord::Migration[8.0]
  def change
    create_table :thread_agent_notion_databases do |t|
      t.references :notion_workspace, null: false, foreign_key: { to_table: :thread_agent_notion_workspaces }
      t.string :notion_database_id, null: false, limit: 255
      t.string :name, null: false, limit: 255
      t.string :status, null: false, default: "active"

      t.timestamps null: false
    end

    # Indexes for performance and uniqueness
    add_index :thread_agent_notion_databases, [ :notion_workspace_id, :notion_database_id ], unique: true
    add_index :thread_agent_notion_databases, :status
  end
end
