class CreateThreadAgentTemplates < ActiveRecord::Migration[8.0]
  def change
    create_table :thread_agent_templates do |t|
      t.string :name, null: false, limit: 100
      t.text :description, limit: 500
      t.text :content, null: false
      t.string :status, null: false, default: "active"
      t.references :notion_database, null: true, foreign_key: { to_table: :thread_agent_notion_databases }

      t.timestamps null: false
    end

    add_index :thread_agent_templates, :name, unique: true
    add_index :thread_agent_templates, :status
  end
end
