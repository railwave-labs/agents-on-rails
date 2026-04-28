# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_04_27_142712) do
  create_table "agent_runs", force: :cascade do |t|
    t.string "workflow_name", null: false
    t.string "status", default: "pending", null: false
    t.text "input_data"
    t.text "output_data"
    t.text "error_message"
    t.json "steps", default: []
    t.datetime "started_at"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "slack_message_id"
    t.string "slack_channel_id"
    t.integer "template_id"
    t.string "slack_thread_ts", limit: 255
    t.string "kind", default: "thread_capture", null: false
    t.integer "cost_cents"
    t.json "token_usage"
    t.index ["kind"], name: "index_agent_runs_on_kind"
    t.index ["slack_channel_id", "slack_message_id"], name: "index_agent_runs_on_slack_channel_id_and_slack_message_id"
    t.index ["slack_channel_id", "slack_thread_ts"], name: "index_agent_runs_on_slack_channel_id_and_slack_thread_ts"
    t.index ["started_at"], name: "index_agent_runs_on_started_at"
    t.index ["status"], name: "index_agent_runs_on_status"
    t.index ["template_id"], name: "index_agent_runs_on_template_id"
    t.index ["workflow_name", "status"], name: "index_agent_runs_on_workflow_name_and_status"
  end

  create_table "notion_databases", force: :cascade do |t|
    t.integer "notion_workspace_id", null: false
    t.string "notion_database_id", limit: 255, null: false
    t.string "name", limit: 255, null: false
    t.string "status", default: "active", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["notion_workspace_id", "notion_database_id"], name: "idx_on_notion_workspace_id_notion_database_id_c7138f7981", unique: true
    t.index ["notion_workspace_id"], name: "index_notion_databases_on_notion_workspace_id"
    t.index ["status"], name: "index_notion_databases_on_status"
  end

  create_table "notion_workspaces", force: :cascade do |t|
    t.string "name", limit: 100, null: false
    t.string "notion_workspace_id", limit: 255, null: false
    t.text "access_token", null: false
    t.string "slack_team_id", limit: 255, null: false
    t.string "status", default: "active", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["notion_workspace_id"], name: "index_notion_workspaces_on_notion_workspace_id", unique: true
    t.index ["slack_team_id"], name: "index_notion_workspaces_on_slack_team_id", unique: true
    t.index ["status"], name: "index_notion_workspaces_on_status"
  end

  create_table "templates", force: :cascade do |t|
    t.string "name", limit: 100, null: false
    t.text "description", limit: 500
    t.text "content", null: false
    t.string "status", default: "active", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "notion_database_id", null: false
    t.json "property_schema"
    t.index ["name"], name: "index_templates_on_name", unique: true
    t.index ["notion_database_id"], name: "index_templates_on_notion_database_id"
    t.index ["status"], name: "index_templates_on_status"
  end

  add_foreign_key "agent_runs", "templates"
  add_foreign_key "notion_databases", "notion_workspaces"
  add_foreign_key "templates", "notion_databases"
end
