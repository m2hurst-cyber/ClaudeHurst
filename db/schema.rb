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

ActiveRecord::Schema[7.1].define(version: 2026_04_19_153049) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "activities", force: :cascade do |t|
    t.string "subject_type", null: false
    t.bigint "subject_id", null: false
    t.bigint "user_id"
    t.string "kind", null: false
    t.datetime "occurred_at", null: false
    t.text "body"
    t.integer "duration_minutes"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["kind"], name: "index_activities_on_kind"
    t.index ["occurred_at"], name: "index_activities_on_occurred_at"
    t.index ["subject_type", "subject_id"], name: "index_activities_on_subject"
    t.index ["user_id"], name: "index_activities_on_user_id"
  end

  create_table "audit_logs", force: :cascade do |t|
    t.bigint "user_id"
    t.string "subject_type"
    t.bigint "subject_id"
    t.string "action", null: false
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.index ["action"], name: "index_audit_logs_on_action"
    t.index ["created_at"], name: "index_audit_logs_on_created_at"
    t.index ["subject_type", "subject_id"], name: "index_audit_logs_on_subject"
    t.index ["user_id"], name: "index_audit_logs_on_user_id"
  end

  create_table "bom_items", force: :cascade do |t|
    t.bigint "bom_id", null: false
    t.bigint "raw_material_id", null: false
    t.decimal "quantity_per_unit", precision: 14, scale: 6, null: false
    t.string "uom", null: false
    t.integer "position", default: 0, null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bom_id", "raw_material_id"], name: "index_bom_items_on_bom_id_and_raw_material_id", unique: true
    t.index ["bom_id"], name: "index_bom_items_on_bom_id"
    t.index ["raw_material_id"], name: "index_bom_items_on_raw_material_id"
  end

  create_table "boms", force: :cascade do |t|
    t.bigint "product_id", null: false
    t.integer "version", default: 1, null: false
    t.boolean "active", default: true, null: false
    t.integer "yield_units", default: 1, null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id", "version"], name: "index_boms_on_product_id_and_version", unique: true
    t.index ["product_id"], name: "index_boms_on_product_id"
  end

  create_table "companies", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.string "website"
    t.string "industry"
    t.string "status", default: "prospect", null: false
    t.jsonb "billing_address", default: {}
    t.jsonb "shipping_address", default: {}
    t.bigint "owner_id"
    t.text "notes"
    t.datetime "discarded_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["discarded_at"], name: "index_companies_on_discarded_at"
    t.index ["name"], name: "index_companies_on_name"
    t.index ["owner_id"], name: "index_companies_on_owner_id"
    t.index ["slug"], name: "index_companies_on_slug", unique: true
    t.index ["status"], name: "index_companies_on_status"
  end

  create_table "contacts", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.string "first_name", null: false
    t.string "last_name"
    t.string "title"
    t.string "email"
    t.string "phone"
    t.boolean "primary", default: false, null: false
    t.datetime "discarded_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_contacts_on_company_id"
    t.index ["discarded_at"], name: "index_contacts_on_discarded_at"
    t.index ["email"], name: "index_contacts_on_email"
  end

  create_table "contract_pricing_tiers", force: :cascade do |t|
    t.bigint "contract_id", null: false
    t.bigint "product_id", null: false
    t.integer "min_quantity", default: 1, null: false
    t.bigint "unit_price_cents", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["contract_id", "product_id", "min_quantity"], name: "idx_contract_pricing_uniq", unique: true
    t.index ["contract_id"], name: "index_contract_pricing_tiers_on_contract_id"
    t.index ["product_id"], name: "index_contract_pricing_tiers_on_product_id"
  end

  create_table "contracts", force: :cascade do |t|
    t.string "number", null: false
    t.bigint "company_id", null: false
    t.string "title", null: false
    t.string "status", default: "draft", null: false
    t.date "start_on"
    t.date "end_on"
    t.string "payment_terms", default: "net_30", null: false
    t.integer "minimum_run_units"
    t.datetime "signed_at"
    t.datetime "countersigned_at"
    t.text "terms"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_contracts_on_company_id"
    t.index ["number"], name: "index_contracts_on_number", unique: true
    t.index ["status"], name: "index_contracts_on_status"
  end

  create_table "deals", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.bigint "owner_id"
    t.string "name", null: false
    t.bigint "amount_cents", default: 0, null: false
    t.string "currency", default: "USD", null: false
    t.string "stage", default: "lead", null: false
    t.date "expected_close_on"
    t.integer "probability", default: 10
    t.datetime "closed_at"
    t.string "lost_reason"
    t.text "notes"
    t.datetime "discarded_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_deals_on_company_id"
    t.index ["discarded_at"], name: "index_deals_on_discarded_at"
    t.index ["owner_id"], name: "index_deals_on_owner_id"
    t.index ["stage"], name: "index_deals_on_stage"
  end

  create_table "finished_good_lots", force: :cascade do |t|
    t.bigint "product_id", null: false
    t.bigint "production_run_id", null: false
    t.string "lot_code", null: false
    t.date "produced_on", null: false
    t.date "best_by_on"
    t.integer "quantity_produced", null: false
    t.integer "quantity_on_hand", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["lot_code"], name: "index_finished_good_lots_on_lot_code", unique: true
    t.index ["product_id"], name: "index_finished_good_lots_on_product_id"
    t.index ["production_run_id"], name: "index_finished_good_lots_on_production_run_id"
  end

  create_table "finished_good_movements", force: :cascade do |t|
    t.bigint "finished_good_lot_id", null: false
    t.bigint "user_id"
    t.string "reference_type"
    t.bigint "reference_id"
    t.string "kind", null: false
    t.integer "quantity", null: false
    t.datetime "occurred_at", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["finished_good_lot_id"], name: "index_finished_good_movements_on_finished_good_lot_id"
    t.index ["kind"], name: "index_finished_good_movements_on_kind"
    t.index ["occurred_at"], name: "index_finished_good_movements_on_occurred_at"
    t.index ["reference_type", "reference_id"], name: "index_finished_good_movements_on_reference"
    t.index ["user_id"], name: "index_finished_good_movements_on_user_id"
  end

  create_table "invoice_line_items", force: :cascade do |t|
    t.bigint "invoice_id", null: false
    t.bigint "product_id"
    t.string "description", null: false
    t.decimal "quantity", precision: 12, scale: 3, default: "1.0", null: false
    t.bigint "unit_price_cents", default: 0, null: false
    t.decimal "tax_rate", precision: 6, scale: 4, default: "0.0", null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["invoice_id"], name: "index_invoice_line_items_on_invoice_id"
    t.index ["product_id"], name: "index_invoice_line_items_on_product_id"
  end

  create_table "invoices", force: :cascade do |t|
    t.string "number", null: false
    t.bigint "company_id", null: false
    t.bigint "contract_id"
    t.bigint "production_run_id"
    t.string "status", default: "draft", null: false
    t.date "issued_on"
    t.date "due_on"
    t.date "paid_on"
    t.bigint "subtotal_cents", default: 0, null: false
    t.bigint "tax_cents", default: 0, null: false
    t.bigint "total_cents", default: 0, null: false
    t.bigint "balance_cents", default: 0, null: false
    t.string "currency", default: "USD", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_invoices_on_company_id"
    t.index ["contract_id"], name: "index_invoices_on_contract_id"
    t.index ["due_on"], name: "index_invoices_on_due_on"
    t.index ["number"], name: "index_invoices_on_number", unique: true
    t.index ["production_run_id"], name: "index_invoices_on_production_run_id"
    t.index ["status"], name: "index_invoices_on_status"
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
    t.datetime "emailed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["read_at"], name: "index_notifications_on_read_at"
    t.index ["subject_type", "subject_id"], name: "index_notifications_on_subject"
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "number_sequences", force: :cascade do |t|
    t.string "scope", null: false
    t.integer "year", null: false
    t.integer "last_value", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["scope", "year"], name: "index_number_sequences_on_scope_and_year", unique: true
  end

  create_table "payments", force: :cascade do |t|
    t.bigint "invoice_id", null: false
    t.bigint "amount_cents", null: false
    t.date "received_on", null: false
    t.string "method", default: "ach", null: false
    t.string "reference"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["invoice_id"], name: "index_payments_on_invoice_id"
    t.index ["received_on"], name: "index_payments_on_received_on"
  end

  create_table "production_lines", force: :cascade do |t|
    t.string "name", null: false
    t.string "code", null: false
    t.integer "hourly_capacity"
    t.boolean "active", default: true, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_production_lines_on_code", unique: true
  end

  create_table "production_run_consumptions", force: :cascade do |t|
    t.bigint "production_run_id", null: false
    t.bigint "raw_material_lot_id", null: false
    t.decimal "quantity_planned", precision: 14, scale: 4, default: "0.0", null: false
    t.decimal "quantity_actual", precision: 14, scale: 4
    t.string "uom", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["production_run_id", "raw_material_lot_id"], name: "idx_run_consumption", unique: true
    t.index ["production_run_id"], name: "index_production_run_consumptions_on_production_run_id"
    t.index ["raw_material_lot_id"], name: "index_production_run_consumptions_on_raw_material_lot_id"
  end

  create_table "production_runs", force: :cascade do |t|
    t.string "number", null: false
    t.bigint "product_id", null: false
    t.bigint "bom_id"
    t.bigint "production_line_id", null: false
    t.bigint "owner_id"
    t.datetime "scheduled_start", null: false
    t.datetime "scheduled_end"
    t.datetime "actual_start"
    t.datetime "actual_end"
    t.integer "planned_units", null: false
    t.integer "actual_units"
    t.string "status", default: "planned", null: false
    t.string "batch_code"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bom_id"], name: "index_production_runs_on_bom_id"
    t.index ["number"], name: "index_production_runs_on_number", unique: true
    t.index ["owner_id"], name: "index_production_runs_on_owner_id"
    t.index ["product_id"], name: "index_production_runs_on_product_id"
    t.index ["production_line_id"], name: "index_production_runs_on_production_line_id"
    t.index ["scheduled_start"], name: "index_production_runs_on_scheduled_start"
    t.index ["status"], name: "index_production_runs_on_status"
  end

  create_table "products", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.string "sku", null: false
    t.string "name", null: false
    t.string "format"
    t.integer "case_pack", default: 24
    t.string "gtin"
    t.boolean "active", default: true, null: false
    t.text "description"
    t.datetime "discarded_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "sku"], name: "index_products_on_company_id_and_sku", unique: true
    t.index ["company_id"], name: "index_products_on_company_id"
    t.index ["discarded_at"], name: "index_products_on_discarded_at"
  end

  create_table "quote_line_items", force: :cascade do |t|
    t.bigint "quote_id", null: false
    t.bigint "product_id"
    t.string "description", null: false
    t.decimal "quantity", precision: 12, scale: 3, default: "1.0", null: false
    t.bigint "unit_price_cents", default: 0, null: false
    t.decimal "tax_rate", precision: 6, scale: 4, default: "0.0", null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_quote_line_items_on_product_id"
    t.index ["quote_id"], name: "index_quote_line_items_on_quote_id"
  end

  create_table "quotes", force: :cascade do |t|
    t.string "number", null: false
    t.bigint "company_id", null: false
    t.bigint "deal_id"
    t.bigint "contact_id"
    t.string "status", default: "draft", null: false
    t.date "issued_on"
    t.date "expires_on"
    t.bigint "subtotal_cents", default: 0, null: false
    t.bigint "tax_cents", default: 0, null: false
    t.bigint "total_cents", default: 0, null: false
    t.string "currency", default: "USD", null: false
    t.text "notes"
    t.text "terms"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_quotes_on_company_id"
    t.index ["contact_id"], name: "index_quotes_on_contact_id"
    t.index ["deal_id"], name: "index_quotes_on_deal_id"
    t.index ["number"], name: "index_quotes_on_number", unique: true
    t.index ["status"], name: "index_quotes_on_status"
  end

  create_table "raw_material_lots", force: :cascade do |t|
    t.bigint "raw_material_id", null: false
    t.string "lot_code", null: false
    t.date "received_on", null: false
    t.date "expires_on"
    t.decimal "quantity_received", precision: 14, scale: 4, null: false
    t.decimal "quantity_on_hand", precision: 14, scale: 4, null: false
    t.string "supplier"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["raw_material_id", "lot_code"], name: "index_raw_material_lots_on_raw_material_id_and_lot_code", unique: true
    t.index ["raw_material_id"], name: "index_raw_material_lots_on_raw_material_id"
    t.index ["received_on"], name: "index_raw_material_lots_on_received_on"
  end

  create_table "raw_materials", force: :cascade do |t|
    t.string "code", null: false
    t.string "name", null: false
    t.string "category", null: false
    t.string "uom", default: "each", null: false
    t.decimal "reorder_point", precision: 12, scale: 2, default: "0.0"
    t.string "owned_by", default: "copacker", null: false
    t.bigint "owned_by_company_id"
    t.text "description"
    t.datetime "discarded_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category"], name: "index_raw_materials_on_category"
    t.index ["code"], name: "index_raw_materials_on_code", unique: true
    t.index ["discarded_at"], name: "index_raw_materials_on_discarded_at"
    t.index ["owned_by_company_id"], name: "index_raw_materials_on_owned_by_company_id"
  end

  create_table "reminders", force: :cascade do |t|
    t.string "subject_type"
    t.bigint "subject_id"
    t.bigint "user_id", null: false
    t.datetime "remind_at", null: false
    t.string "channel", default: "in_app", null: false
    t.string "recurrence", default: "none", null: false
    t.text "message", null: false
    t.datetime "fired_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["fired_at"], name: "index_reminders_on_fired_at"
    t.index ["remind_at"], name: "index_reminders_on_remind_at"
    t.index ["subject_type", "subject_id"], name: "index_reminders_on_subject"
    t.index ["user_id"], name: "index_reminders_on_user_id"
  end

  create_table "tasks", force: :cascade do |t|
    t.string "subject_type"
    t.bigint "subject_id"
    t.bigint "assignee_id"
    t.string "title", null: false
    t.text "description"
    t.date "due_on"
    t.datetime "completed_at"
    t.string "priority", default: "normal", null: false
    t.datetime "discarded_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["assignee_id"], name: "index_tasks_on_assignee_id"
    t.index ["completed_at"], name: "index_tasks_on_completed_at"
    t.index ["discarded_at"], name: "index_tasks_on_discarded_at"
    t.index ["due_on"], name: "index_tasks_on_due_on"
    t.index ["subject_type", "subject_id"], name: "index_tasks_on_subject"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.string "first_name"
    t.string "last_name"
    t.string "role", default: "sales", null: false
    t.boolean "active", default: true, null: false
    t.datetime "last_seen_at"
    t.datetime "discarded_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["discarded_at"], name: "index_users_on_discarded_at"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["role"], name: "index_users_on_role"
  end

  create_table "versions", force: :cascade do |t|
    t.string "whodunnit"
    t.datetime "created_at"
    t.bigint "item_id", null: false
    t.string "item_type", null: false
    t.string "event", null: false
    t.text "object"
    t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "activities", "users"
  add_foreign_key "audit_logs", "users"
  add_foreign_key "bom_items", "boms"
  add_foreign_key "bom_items", "raw_materials"
  add_foreign_key "boms", "products"
  add_foreign_key "companies", "users", column: "owner_id"
  add_foreign_key "contacts", "companies"
  add_foreign_key "contract_pricing_tiers", "contracts"
  add_foreign_key "contract_pricing_tiers", "products"
  add_foreign_key "contracts", "companies"
  add_foreign_key "deals", "companies"
  add_foreign_key "deals", "users", column: "owner_id"
  add_foreign_key "finished_good_lots", "production_runs"
  add_foreign_key "finished_good_lots", "products"
  add_foreign_key "finished_good_movements", "finished_good_lots"
  add_foreign_key "finished_good_movements", "users"
  add_foreign_key "invoice_line_items", "invoices"
  add_foreign_key "invoice_line_items", "products"
  add_foreign_key "invoices", "companies"
  add_foreign_key "invoices", "contracts"
  add_foreign_key "invoices", "production_runs"
  add_foreign_key "notifications", "users"
  add_foreign_key "payments", "invoices"
  add_foreign_key "production_run_consumptions", "production_runs"
  add_foreign_key "production_run_consumptions", "raw_material_lots"
  add_foreign_key "production_runs", "boms"
  add_foreign_key "production_runs", "production_lines"
  add_foreign_key "production_runs", "products"
  add_foreign_key "production_runs", "users", column: "owner_id"
  add_foreign_key "products", "companies"
  add_foreign_key "quote_line_items", "products"
  add_foreign_key "quote_line_items", "quotes"
  add_foreign_key "quotes", "companies"
  add_foreign_key "quotes", "contacts"
  add_foreign_key "quotes", "deals"
  add_foreign_key "raw_material_lots", "raw_materials"
  add_foreign_key "raw_materials", "companies", column: "owned_by_company_id"
  add_foreign_key "reminders", "users"
  add_foreign_key "tasks", "users", column: "assignee_id"
end
