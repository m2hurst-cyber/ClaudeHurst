module SkillCapture
  # Human-readable descriptions of the app's workflow steps. Used to turn a
  # bare "production_runs#release" into an instruction a colleague can follow,
  # and to tell the LLM what each step means without sending any record data.
  module Catalog
    DOMAINS = {
      "sales" => %w[companies contacts deals activities quotes contracts contract_pricing_tiers tasks reminders],
      "ops" => %w[products boms raw_materials raw_material_lots production_lines production_runs finished_good_lots finished_good_movements],
      "finance" => %w[invoices payments]
    }.freeze

    STEPS = {
      "companies#create" => "Create the company record (Companies → New)",
      "companies#update" => "Update the company record",
      "contacts#create" => "Add a contact to the company",
      "deals#create" => "Open a new deal for the company",
      "deals#update" => "Update the deal details",
      "deals#advance" => "Advance the deal to its next pipeline stage",
      "activities#create" => "Log an activity (call, email, meeting) against the record",
      "tasks#create" => "Create a follow-up task",
      "tasks#update" => "Update or complete the task",
      "reminders#create" => "Schedule a reminder",
      "quotes#create" => "Create a quote from the deal",
      "quotes#update" => "Edit the quote line items",
      "quotes#send_out" => "Send the quote (generates the PDF and emails the contact)",
      "quotes#mark_accepted" => "Mark the quote accepted",
      "quotes#mark_rejected" => "Mark the quote rejected",
      "contracts#create" => "Create the contract",
      "contract_pricing_tiers#create" => "Add a pricing tier to the contract",
      "contracts#mark_signed" => "Mark the contract signed",
      "contracts#activate" => "Activate the contract",
      "products#create" => "Create the product for the brand",
      "boms#create" => "Create the bill of materials for the product",
      "boms#update" => "Update the bill of materials",
      "raw_materials#create" => "Register the raw material",
      "raw_material_lots#create" => "Receive a raw-material lot (quantity, lot code, expiry)",
      "production_runs#create" => "Schedule a production run (product, BOM, line, planned units)",
      "production_runs#update" => "Adjust the production run plan",
      "production_runs#release" => "Release the run — snapshots the BOM and reserves raw-material lots",
      "production_runs#start_run" => "Start the run on the line",
      "production_runs#complete" => "Complete the run with actual units — consumes lots and creates the finished-good lot",
      "production_runs#close" => "Close the run",
      "production_runs#cancel" => "Cancel the run (releases reservations)",
      "production_runs#create_invoice" => "Create the invoice from the completed run (pre-filled from the contract tier)",
      "finished_good_movements#create" => "Record a finished-good movement (ship, adjust, transfer)",
      "invoices#create" => "Create the invoice",
      "invoices#update" => "Edit the invoice",
      "invoices#send_out" => "Send the invoice (PDF + email)",
      "invoices#void_it" => "Void the invoice",
      "payments#create" => "Record a payment against the invoice"
    }.freeze

    module_function

    def describe(workflow_key)
      STEPS[workflow_key] || begin
        controller, action = workflow_key.split("#", 2)
        "#{action.to_s.humanize} #{controller.to_s.singularize.humanize.downcase}"
      end
    end

    def domain_for(workflow_key)
      controller = workflow_key.split("#").first.to_s.split("/").last
      DOMAINS.find { |_, list| list.include?(controller) }&.first || "general"
    end

    # The dominant domain of a multi-step workflow decides which role reviews it.
    def domain_for_steps(steps)
      steps.map { |s| domain_for(s) }.tally.max_by { |_, n| n }&.first || "general"
    end
  end
end
