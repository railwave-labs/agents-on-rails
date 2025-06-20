class AddNotionDatabaseToThreadAgentTemplates < ActiveRecord::Migration[8.0]
  def change
    add_reference :thread_agent_templates, :notion_database, null: false,
                  foreign_key: { to_table: :thread_agent_notion_databases }
  end
end
