class CreateThreadAgentNotionWorkspaces < ActiveRecord::Migration[8.0]
  def change
    create_table :thread_agent_notion_workspaces do |t|
      t.string :name, null: false, limit: 100
      t.string :notion_workspace_id, null: false, limit: 255
      t.text :access_token, null: false  # Encrypted token for Notion API
      t.string :slack_team_id, null: false, limit: 255  # Links to Slack workspace
      t.string :status, null: false, default: "active"

      t.timestamps null: false
    end

    # Indexes for performance
    add_index :thread_agent_notion_workspaces, :slack_team_id, unique: true
    add_index :thread_agent_notion_workspaces, :notion_workspace_id, unique: true
    add_index :thread_agent_notion_workspaces, :status
  end
end
