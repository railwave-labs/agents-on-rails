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

ActiveRecord::Schema[8.0].define(version: 2025_06_20_102150) do
  create_table "thread_agent_workflow_runs", force: :cascade do |t|
    t.string "workflow_name", limit: 255, null: false
    t.string "status", default: "pending", null: false
    t.string "thread_id", limit: 255
    t.string "external_id", limit: 255
    t.json "input_payload"
    t.json "output_payload"
    t.text "error_message", limit: 2000
    t.datetime "started_at"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "steps", default: []
    t.index ["created_at"], name: "index_thread_agent_workflow_runs_on_created_at"
    t.index ["external_id"], name: "index_thread_agent_workflow_runs_on_external_id"
    t.index ["status"], name: "index_thread_agent_workflow_runs_on_status"
    t.index ["thread_id"], name: "index_thread_agent_workflow_runs_on_thread_id"
    t.index ["workflow_name", "status"], name: "index_thread_agent_workflow_runs_on_workflow_name_and_status"
    t.index ["workflow_name"], name: "index_thread_agent_workflow_runs_on_workflow_name"
  end
end
