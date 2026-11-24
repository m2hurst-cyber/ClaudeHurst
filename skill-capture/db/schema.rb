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

ActiveRecord::Schema[7.2].define(version: 2026_11_24_000018) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "action_definitions", force: :cascade do |t|
    t.string "key", null: false
    t.string "label", null: false
    t.string "domain"
    t.bigint "source_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_action_definitions_on_key", unique: true
    t.index ["source_id"], name: "index_action_definitions_on_source_id"
  end

  create_table "addin_commands", force: :cascade do |t|
    t.bigint "sender_id"
    t.bigint "target_user_id"
    t.bigint "target_source_id"
    t.string "kind", null: false
    t.jsonb "payload", default: {}, null: false
    t.string "status", default: "pending", null: false
    t.datetime "delivered_at"
    t.string "delivered_to"
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["sender_id"], name: "index_addin_commands_on_sender_id"
    t.index ["target_source_id", "status"], name: "index_addin_commands_on_target_source_id_and_status"
    t.index ["target_source_id"], name: "index_addin_commands_on_target_source_id"
    t.index ["target_user_id", "status"], name: "index_addin_commands_on_target_user_id_and_status"
    t.index ["target_user_id"], name: "index_addin_commands_on_target_user_id"
  end

  create_table "addin_tokens", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "token_digest", null: false
    t.string "host"
    t.string "platform"
    t.datetime "last_used_at"
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["token_digest"], name: "index_addin_tokens_on_token_digest", unique: true
    t.index ["user_id"], name: "index_addin_tokens_on_user_id"
  end

  create_table "audit_logs", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "source_id"
    t.string "subject_type"
    t.bigint "subject_id"
    t.string "action", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.index ["action"], name: "index_audit_logs_on_action"
    t.index ["created_at"], name: "index_audit_logs_on_created_at"
    t.index ["source_id"], name: "index_audit_logs_on_source_id"
    t.index ["subject_type", "subject_id"], name: "index_audit_logs_on_subject"
    t.index ["user_id"], name: "index_audit_logs_on_user_id"
  end

  create_table "bounties", force: :cascade do |t|
    t.string "skill_name", null: false
    t.string "status", default: "open", null: false
    t.decimal "pool", precision: 12, scale: 2, default: "0.0", null: false
    t.datetime "accrued_until"
    t.float "opened_index"
    t.float "baseline_index"
    t.datetime "fix_at"
    t.string "fix_skill_name"
    t.integer "fix_version"
    t.bigint "solver_id"
    t.float "result_index"
    t.float "improvement"
    t.decimal "payout", precision: 12, scale: 2
    t.bigint "approved_by_id"
    t.datetime "approved_at"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["approved_by_id"], name: "index_bounties_on_approved_by_id"
    t.index ["skill_name", "status"], name: "index_bounties_on_skill_name_and_status"
    t.index ["solver_id"], name: "index_bounties_on_solver_id"
  end

  create_table "credit_entries", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "bounty_id"
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.string "reason", null: false
    t.datetime "created_at", null: false
    t.bigint "skill_transfer_id"
    t.index ["bounty_id"], name: "index_credit_entries_on_bounty_id"
    t.index ["skill_transfer_id"], name: "index_credit_entries_on_skill_transfer_id"
    t.index ["user_id"], name: "index_credit_entries_on_user_id"
  end

  create_table "fields", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.string "path", null: false
    t.bigint "parent_id"
    t.integer "position", default: 0, null: false
    t.string "keywords", default: [], null: false, array: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "created_by_id"
    t.index ["created_by_id"], name: "index_fields_on_created_by_id"
    t.index ["parent_id"], name: "index_fields_on_parent_id"
    t.index ["path"], name: "index_fields_on_path", unique: true
  end

  create_table "formula_commands", force: :cascade do |t|
    t.string "provider", null: false
    t.string "key", null: false
    t.string "name", null: false
    t.string "category", default: "Other", null: false
    t.text "syntax", null: false
    t.jsonb "defaults", default: {}, null: false
    t.text "description"
    t.string "status", default: "unverified", null: false
    t.string "origin", default: "pack", null: false
    t.text "verification_note"
    t.bigint "verified_by_id"
    t.datetime "verified_at"
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_formula_commands_on_created_by_id"
    t.index ["provider", "category"], name: "index_formula_commands_on_provider_and_category"
    t.index ["provider", "key"], name: "index_formula_commands_on_provider_and_key", unique: true
    t.index ["verified_by_id"], name: "index_formula_commands_on_verified_by_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "subject_type"
    t.bigint "subject_id"
    t.string "kind", null: false
    t.string "title", null: false
    t.text "body"
    t.string "url"
    t.datetime "read_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["subject_type", "subject_id"], name: "index_notifications_on_subject"
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "playbook_runs", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "playbook_key", null: false
    t.string "reference", null: false
    t.jsonb "answers", default: {}, null: false
    t.string "done", default: [], null: false, array: true
    t.string "status", default: "open", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "legs", default: {}, null: false
    t.jsonb "inputs", default: {}, null: false
    t.bigint "reviewer_id"
    t.datetime "reviewed_at"
    t.index ["reviewer_id"], name: "index_playbook_runs_on_reviewer_id"
    t.index ["user_id", "status"], name: "index_playbook_runs_on_user_id_and_status"
    t.index ["user_id"], name: "index_playbook_runs_on_user_id"
  end

  create_table "pricing_schedules", force: :cascade do |t|
    t.string "currency", default: "credits", null: false
    t.decimal "base_price", precision: 12, scale: 2, default: "10.0", null: false
    t.jsonb "tiers", default: [], null: false
    t.integer "window_days", default: 7, null: false
    t.integer "min_trips", default: 5, null: false
    t.decimal "pool_share", precision: 5, scale: 2, default: "1.0", null: false
    t.string "bounty_tier", default: "heavy", null: false
    t.integer "measure_min_trips", default: 5, null: false
    t.integer "measure_max_days", default: 21, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "promotion_policies", force: :cascade do |t|
    t.string "initial_stage", default: "local", null: false
    t.integer "firm_min_trips", default: 3, null: false
    t.integer "firm_min_people", default: 2, null: false
    t.integer "firm_min_score", default: 2, null: false
    t.integer "market_min_days", default: 14, null: false
    t.integer "market_min_score", default: 5, null: false
    t.string "market_max_tier", default: "slow", null: false
    t.boolean "market_requires_directions", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "promotions", force: :cascade do |t|
    t.string "skill_name", null: false
    t.integer "skill_version", null: false
    t.string "from_stage", null: false
    t.string "to_stage", null: false
    t.string "status", default: "open", null: false
    t.string "replaces_name"
    t.text "pitch"
    t.jsonb "checks", default: [], null: false
    t.boolean "waived", default: false, null: false
    t.bigint "requested_by_id"
    t.bigint "decided_by_id"
    t.datetime "decided_at"
    t.text "decision_notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["decided_by_id"], name: "index_promotions_on_decided_by_id"
    t.index ["requested_by_id"], name: "index_promotions_on_requested_by_id"
    t.index ["skill_name", "status"], name: "index_promotions_on_skill_name_and_status"
  end

  create_table "protocols", force: :cascade do |t|
    t.string "key", null: false
    t.boolean "enabled", default: true, null: false
    t.jsonb "settings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_protocols_on_key", unique: true
  end

  create_table "resource_folders", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.string "path", null: false
    t.bigint "parent_id"
    t.string "audience", default: "firm", null: false
    t.string "areas", default: [], null: false, array: true
    t.text "description"
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_resource_folders_on_created_by_id"
    t.index ["parent_id"], name: "index_resource_folders_on_parent_id"
    t.index ["path"], name: "index_resource_folders_on_path", unique: true
  end

  create_table "resources", force: :cascade do |t|
    t.bigint "folder_id", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.text "description"
    t.string "kind", default: "file", null: false
    t.string "url"
    t.string "filename"
    t.string "content_type"
    t.integer "byte_size"
    t.string "checksum"
    t.binary "content"
    t.integer "version", default: 1, null: false
    t.bigint "uploaded_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["folder_id", "slug"], name: "index_resources_on_folder_id_and_slug", unique: true
    t.index ["folder_id"], name: "index_resources_on_folder_id"
    t.index ["uploaded_by_id"], name: "index_resources_on_uploaded_by_id"
  end

  create_table "rest_stops", force: :cascade do |t|
    t.string "skill_name", null: false
    t.integer "skill_version", null: false
    t.bigint "skill_id"
    t.string "kind", default: "auto", null: false
    t.string "reason", null: false
    t.string "label"
    t.jsonb "snapshot", null: false
    t.string "checksum", null: false
    t.boolean "pinned", default: false, null: false
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.index ["created_by_id"], name: "index_rest_stops_on_created_by_id"
    t.index ["skill_id"], name: "index_rest_stops_on_skill_id"
    t.index ["skill_name", "created_at"], name: "index_rest_stops_on_skill_name_and_created_at"
  end

  create_table "return_documents", force: :cascade do |t|
    t.bigint "playbook_run_id", null: false
    t.string "kind"
    t.string "label"
    t.text "filename"
    t.text "payer"
    t.string "content_type", null: false
    t.integer "byte_size", null: false
    t.string "checksum", null: false
    t.text "content", null: false
    t.text "fields_json"
    t.integer "tax_year"
    t.string "status", default: "uploaded", null: false
    t.string "read_by"
    t.integer "confidence"
    t.text "notes"
    t.bigint "uploaded_by_id"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["playbook_run_id", "checksum"], name: "index_return_documents_on_playbook_run_id_and_checksum", unique: true
    t.index ["playbook_run_id"], name: "index_return_documents_on_playbook_run_id"
    t.index ["uploaded_by_id"], name: "index_return_documents_on_uploaded_by_id"
  end

  create_table "situations", force: :cascade do |t|
    t.string "playbook_key", null: false
    t.string "key", null: false
    t.text "question", null: false
    t.string "after_skill", null: false
    t.string "branch_skill"
    t.string "forms", default: [], null: false, array: true
    t.string "keywords", default: [], null: false, array: true
    t.string "status", default: "active", null: false
    t.integer "position", default: 0, null: false
    t.bigint "candidate_id"
    t.bigint "proposed_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["candidate_id"], name: "index_situations_on_candidate_id"
    t.index ["playbook_key", "key"], name: "index_situations_on_playbook_key_and_key", unique: true
    t.index ["proposed_by_id"], name: "index_situations_on_proposed_by_id"
  end

  create_table "skill_candidates", force: :cascade do |t|
    t.string "signature", null: false
    t.jsonb "steps", default: [], null: false
    t.string "domain"
    t.string "status", default: "detected", null: false
    t.string "origin", default: "detected", null: false
    t.integer "occurrence_count", default: 0, null: false
    t.integer "distinct_actor_count", default: 0, null: false
    t.jsonb "contributors", default: [], null: false
    t.jsonb "example_traces", default: [], null: false
    t.datetime "first_seen_at"
    t.datetime "last_seen_at"
    t.string "draft_name"
    t.string "draft_title"
    t.text "draft_description"
    t.text "draft_body"
    t.string "draft_tags", default: [], null: false, array: true
    t.jsonb "draft_inputs", default: [], null: false
    t.jsonb "draft_outputs", default: [], null: false
    t.string "draft_generator"
    t.datetime "drafted_at"
    t.bigint "requested_by_id"
    t.bigint "reviewer_id"
    t.datetime "reviewed_at"
    t.text "review_notes"
    t.bigint "skill_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "proposal_kind"
    t.bigint "base_skill_id"
    t.jsonb "worksheet"
    t.index ["base_skill_id"], name: "index_skill_candidates_on_base_skill_id"
    t.index ["requested_by_id"], name: "index_skill_candidates_on_requested_by_id"
    t.index ["reviewer_id"], name: "index_skill_candidates_on_reviewer_id"
    t.index ["signature"], name: "index_skill_candidates_on_signature", unique: true
    t.index ["skill_id"], name: "index_skill_candidates_on_skill_id"
    t.index ["status"], name: "index_skill_candidates_on_status"
  end

  create_table "skill_classifications", force: :cascade do |t|
    t.string "skill_name", null: false
    t.bigint "field_id"
    t.string "apps", default: [], null: false, array: true
    t.string "source", default: "rules", null: false
    t.float "confidence"
    t.text "rationale"
    t.boolean "confirmed", default: false, null: false
    t.bigint "updated_by_id"
    t.datetime "inferred_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["field_id"], name: "index_skill_classifications_on_field_id"
    t.index ["skill_name"], name: "index_skill_classifications_on_skill_name", unique: true
    t.index ["updated_by_id"], name: "index_skill_classifications_on_updated_by_id"
  end

  create_table "skill_field_assignments", force: :cascade do |t|
    t.bigint "skill_classification_id", null: false
    t.bigint "field_id", null: false
    t.integer "position", default: 0, null: false
    t.string "source", default: "rules", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["field_id"], name: "index_skill_field_assignments_on_field_id"
    t.index ["skill_classification_id", "field_id"], name: "index_skill_field_assignments_unique", unique: true
    t.index ["skill_classification_id"], name: "index_skill_field_assignments_on_skill_classification_id"
  end

  create_table "skill_grants", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "skill_name", null: false
    t.integer "version", null: false
    t.bigint "transfer_id"
    t.bigint "granted_by_id"
    t.boolean "can_forward", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["granted_by_id"], name: "index_skill_grants_on_granted_by_id"
    t.index ["transfer_id"], name: "index_skill_grants_on_transfer_id"
    t.index ["user_id", "skill_name"], name: "index_skill_grants_on_user_id_and_skill_name", unique: true
    t.index ["user_id"], name: "index_skill_grants_on_user_id"
  end

  create_table "skill_links", force: :cascade do |t|
    t.string "from_node", null: false
    t.string "to_node", null: false
    t.string "origin", null: false
    t.integer "traffic", default: 0, null: false
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_skill_links_on_created_by_id"
    t.index ["from_node", "to_node", "origin"], name: "index_skill_links_on_from_node_and_to_node_and_origin", unique: true
    t.index ["to_node"], name: "index_skill_links_on_to_node"
  end

  create_table "skill_metrics", force: :cascade do |t|
    t.string "name", null: false
    t.integer "trips", default: 0, null: false
    t.integer "people", default: 0, null: false
    t.float "median_minutes"
    t.float "median_wait_minutes"
    t.float "freeflow_minutes"
    t.float "congestion_index"
    t.float "delay_hours", default: 0.0, null: false
    t.string "tier"
    t.decimal "price", precision: 12, scale: 2
    t.jsonb "history", default: [], null: false
    t.datetime "computed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_skill_metrics_on_name", unique: true
  end

  create_table "skill_prompts", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "kind", null: false
    t.string "skill_name"
    t.jsonb "steps", default: [], null: false
    t.jsonb "evidence", default: {}, null: false
    t.integer "occurrences", default: 0, null: false
    t.string "fingerprint", null: false
    t.string "status", default: "open", null: false
    t.datetime "snoozed_until"
    t.datetime "last_seen_at"
    t.datetime "responded_at"
    t.string "response"
    t.bigint "candidate_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["candidate_id"], name: "index_skill_prompts_on_candidate_id"
    t.index ["user_id", "fingerprint"], name: "index_skill_prompts_on_user_id_and_fingerprint", unique: true
    t.index ["user_id", "status"], name: "index_skill_prompts_on_user_id_and_status"
    t.index ["user_id"], name: "index_skill_prompts_on_user_id"
  end

  create_table "skill_resources", force: :cascade do |t|
    t.string "skill_name", null: false
    t.bigint "resource_id", null: false
    t.string "note"
    t.bigint "added_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["added_by_id"], name: "index_skill_resources_on_added_by_id"
    t.index ["resource_id"], name: "index_skill_resources_on_resource_id"
    t.index ["skill_name", "resource_id"], name: "index_skill_resources_on_skill_name_and_resource_id", unique: true
  end

  create_table "skill_transfers", force: :cascade do |t|
    t.bigint "sender_id", null: false
    t.bigint "recipient_id", null: false
    t.jsonb "items", default: [], null: false
    t.decimal "price", precision: 12, scale: 2, default: "0.0", null: false
    t.string "status", default: "offered", null: false
    t.text "message"
    t.boolean "allow_forward", default: false, null: false
    t.datetime "expires_at", null: false
    t.datetime "responded_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["recipient_id", "status"], name: "index_skill_transfers_on_recipient_id_and_status"
    t.index ["recipient_id"], name: "index_skill_transfers_on_recipient_id"
    t.index ["sender_id"], name: "index_skill_transfers_on_sender_id"
  end

  create_table "skill_votes", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "skill_name", null: false
    t.integer "value", null: false
    t.text "comment"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["skill_name"], name: "index_skill_votes_on_skill_name"
    t.index ["user_id", "skill_name"], name: "index_skill_votes_on_user_id_and_skill_name", unique: true
    t.index ["user_id"], name: "index_skill_votes_on_user_id"
  end

  create_table "skills", force: :cascade do |t|
    t.string "name", null: false
    t.integer "version", default: 1, null: false
    t.string "title", null: false
    t.text "description", null: false
    t.text "body", null: false
    t.string "domain"
    t.string "tags", default: [], null: false, array: true
    t.jsonb "inputs", default: [], null: false
    t.jsonb "outputs", default: [], null: false
    t.string "license", default: "Proprietary - internal use only", null: false
    t.string "status", default: "published", null: false
    t.bigint "parent_skill_id"
    t.bigint "published_by_id"
    t.datetime "published_at"
    t.jsonb "source", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "stage", default: "local", null: false
    t.datetime "stage_changed_at"
    t.string "market_audience", default: "global", null: false
    t.index ["name", "version"], name: "index_skills_on_name_and_version", unique: true
    t.index ["parent_skill_id"], name: "index_skills_on_parent_skill_id"
    t.index ["published_by_id"], name: "index_skills_on_published_by_id"
    t.index ["stage"], name: "index_skills_on_stage"
    t.index ["status"], name: "index_skills_on_status"
  end

  create_table "solid_queue_batch_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "batch_id", null: false
    t.datetime "created_at", null: false
    t.index ["batch_id"], name: "index_solid_queue_batch_executions_on_batch_id"
    t.index ["job_id"], name: "index_solid_queue_batch_executions_on_job_id", unique: true
  end

  create_table "solid_queue_batches", force: :cascade do |t|
    t.string "active_job_batch_id"
    t.string "description"
    t.text "on_finish"
    t.text "on_success"
    t.text "on_failure"
    t.text "metadata"
    t.integer "total_jobs", default: 0, null: false
    t.integer "completed_jobs", default: 0, null: false
    t.integer "failed_jobs", default: 0, null: false
    t.datetime "enqueued_at"
    t.datetime "finished_at"
    t.datetime "failed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_batch_id"], name: "index_solid_queue_batches_on_active_job_batch_id", unique: true
    t.index ["finished_at"], name: "index_solid_queue_batches_on_finished_at"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.string "concurrency_key", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "queue_name", null: false
    t.string "class_name", null: false
    t.text "arguments"
    t.integer "priority", default: 0, null: false
    t.string "active_job_id"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "batch_id"
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["batch_id"], name: "index_solid_queue_jobs_on_batch_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.string "queue_name", null: false
    t.datetime "created_at", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.bigint "supervisor_id"
    t.integer "pid", null: false
    t.string "hostname"
    t.text "metadata"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "task_key", null: false
    t.datetime "run_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.string "key", null: false
    t.string "schedule", null: false
    t.string "command", limit: 2048
    t.string "class_name"
    t.text "arguments"
    t.string "queue_name"
    t.integer "priority", default: 0
    t.boolean "static", default: true, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "scheduled_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.string "key", null: false
    t.integer "value", default: 1, null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "sources", force: :cascade do |t|
    t.string "name", null: false
    t.string "kind", default: "custom", null: false
    t.string "token_digest", null: false
    t.string "token_prefix", null: false
    t.boolean "active", default: true, null: false
    t.datetime "last_seen_at"
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_sources_on_created_by_id"
    t.index ["token_digest"], name: "index_sources_on_token_digest", unique: true
  end

  create_table "usage_events", force: :cascade do |t|
    t.bigint "source_id", null: false
    t.string "actor_key", null: false
    t.string "actor_name"
    t.string "session_key", null: false
    t.string "action_key", null: false
    t.string "domain"
    t.string "resource_type"
    t.string "resource_ref"
    t.jsonb "context", default: {}, null: false
    t.datetime "occurred_at", null: false
    t.datetime "created_at", null: false
    t.index ["actor_key", "occurred_at"], name: "index_usage_events_on_actor_key_and_occurred_at"
    t.index ["occurred_at"], name: "index_usage_events_on_occurred_at"
    t.index ["source_id"], name: "index_usage_events_on_source_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.string "name", null: false
    t.string "role", default: "member", null: false
    t.string "domains", default: [], null: false, array: true
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "prompts_checked_at"
    t.string "department"
    t.index ["department"], name: "index_users_on_department"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "waypoint_revisions", force: :cascade do |t|
    t.bigint "waypoint_id", null: false
    t.integer "version", null: false
    t.text "body", null: false
    t.string "note"
    t.bigint "editor_id"
    t.datetime "created_at", null: false
    t.index ["editor_id"], name: "index_waypoint_revisions_on_editor_id"
    t.index ["waypoint_id"], name: "index_waypoint_revisions_on_waypoint_id"
  end

  create_table "waypoints", force: :cascade do |t|
    t.string "key", null: false
    t.string "kind", null: false
    t.string "from_name", null: false
    t.string "to_name"
    t.string "title", null: false
    t.text "body", null: false
    t.string "tags", default: [], null: false, array: true
    t.integer "version", default: 1, null: false
    t.bigint "updated_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "to_tsvector('english'::regconfig, (((COALESCE(title, ''::character varying))::text || ' '::text) || COALESCE(body, ''::text)))", name: "index_waypoints_on_search", using: :gin
    t.index ["from_name"], name: "index_waypoints_on_from_name"
    t.index ["key"], name: "index_waypoints_on_key", unique: true
    t.index ["to_name"], name: "index_waypoints_on_to_name"
    t.index ["updated_by_id"], name: "index_waypoints_on_updated_by_id"
  end

  create_table "worksheet_captures", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "sheet_name", null: false
    t.string "address"
    t.string "provider"
    t.jsonb "observed", default: {}, null: false
    t.jsonb "interpretation", default: {}, null: false
    t.jsonb "inventory", default: [], null: false
    t.jsonb "blueprint", default: {}, null: false
    t.text "structure_md"
    t.text "formulas_md"
    t.text "skill_md"
    t.string "interpreted_by"
    t.string "status", default: "written", null: false
    t.bigint "candidate_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["candidate_id"], name: "index_worksheet_captures_on_candidate_id"
    t.index ["user_id"], name: "index_worksheet_captures_on_user_id"
  end

  add_foreign_key "action_definitions", "sources"
  add_foreign_key "addin_commands", "sources", column: "target_source_id"
  add_foreign_key "addin_commands", "users", column: "sender_id"
  add_foreign_key "addin_commands", "users", column: "target_user_id"
  add_foreign_key "addin_tokens", "users"
  add_foreign_key "audit_logs", "sources"
  add_foreign_key "audit_logs", "users"
  add_foreign_key "bounties", "users", column: "approved_by_id"
  add_foreign_key "bounties", "users", column: "solver_id"
  add_foreign_key "credit_entries", "bounties"
  add_foreign_key "credit_entries", "skill_transfers"
  add_foreign_key "credit_entries", "users"
  add_foreign_key "fields", "fields", column: "parent_id"
  add_foreign_key "fields", "users", column: "created_by_id"
  add_foreign_key "formula_commands", "users", column: "created_by_id"
  add_foreign_key "formula_commands", "users", column: "verified_by_id"
  add_foreign_key "notifications", "users"
  add_foreign_key "playbook_runs", "users"
  add_foreign_key "playbook_runs", "users", column: "reviewer_id"
  add_foreign_key "promotions", "users", column: "decided_by_id"
  add_foreign_key "promotions", "users", column: "requested_by_id"
  add_foreign_key "resource_folders", "resource_folders", column: "parent_id"
  add_foreign_key "resource_folders", "users", column: "created_by_id"
  add_foreign_key "resources", "resource_folders", column: "folder_id"
  add_foreign_key "resources", "users", column: "uploaded_by_id"
  add_foreign_key "rest_stops", "skills"
  add_foreign_key "rest_stops", "users", column: "created_by_id"
  add_foreign_key "return_documents", "playbook_runs"
  add_foreign_key "return_documents", "users", column: "uploaded_by_id"
  add_foreign_key "situations", "skill_candidates", column: "candidate_id"
  add_foreign_key "situations", "users", column: "proposed_by_id"
  add_foreign_key "skill_candidates", "skills"
  add_foreign_key "skill_candidates", "skills", column: "base_skill_id"
  add_foreign_key "skill_candidates", "users", column: "requested_by_id"
  add_foreign_key "skill_candidates", "users", column: "reviewer_id"
  add_foreign_key "skill_classifications", "fields"
  add_foreign_key "skill_classifications", "users", column: "updated_by_id"
  add_foreign_key "skill_field_assignments", "fields"
  add_foreign_key "skill_field_assignments", "skill_classifications"
  add_foreign_key "skill_grants", "skill_transfers", column: "transfer_id"
  add_foreign_key "skill_grants", "users"
  add_foreign_key "skill_grants", "users", column: "granted_by_id"
  add_foreign_key "skill_links", "users", column: "created_by_id"
  add_foreign_key "skill_prompts", "skill_candidates", column: "candidate_id"
  add_foreign_key "skill_prompts", "users"
  add_foreign_key "skill_resources", "resources"
  add_foreign_key "skill_resources", "users", column: "added_by_id"
  add_foreign_key "skill_transfers", "users", column: "recipient_id"
  add_foreign_key "skill_transfers", "users", column: "sender_id"
  add_foreign_key "skill_votes", "users"
  add_foreign_key "skills", "skills", column: "parent_skill_id"
  add_foreign_key "skills", "users", column: "published_by_id"
  add_foreign_key "solid_queue_batch_executions", "solid_queue_batches", column: "batch_id", on_delete: :cascade
  add_foreign_key "solid_queue_batch_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "sources", "users", column: "created_by_id"
  add_foreign_key "usage_events", "sources"
  add_foreign_key "waypoint_revisions", "users", column: "editor_id"
  add_foreign_key "waypoint_revisions", "waypoints"
  add_foreign_key "waypoints", "users", column: "updated_by_id"
  add_foreign_key "worksheet_captures", "skill_candidates", column: "candidate_id"
  add_foreign_key "worksheet_captures", "users"
end
