require "test_helper"

# The roofing and solar sphere: the job workstream with its document jacket, and the estimating and
# billing worksheets built from the job costing formula library.
class RoofingSolarTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    Capture::Taxonomy.ensure_defaults!
    Capture::Models.ensure_defaults!
    @admin = make_user(role: "admin", name: "Ada Admin")
    @pm = make_user(role: "member", domains: %w[field-services jobcost], name: "Pat Manager")
    @rev = make_user(role: "reviewer", domains: %w[field-services jobcost], name: "Robin Reviewer")
    @job = Capture::Playbook.find("roofing-solar")
    @sheets = Capture::Playbook.find("jobcost-worksheets")
  end

  test "both playbooks install clean: the job workstream, its branches, and the worksheet pack" do
    assert_empty @job.problems
    assert_empty @sheets.problems
    r = @job.install!(user: @admin)
    assert_equal 20, r.created.size
    assert_equal %w[field-services firm], [Skill.current("survey-the-roof-and-site").domain, Skill.current("survey-the-roof-and-site").stage]
    assert Capture::SkillStandard.check_skill(Skill.current("bill-the-roofing-job")).ok?

    # the mainline is a road in order, and each situation hangs off its step
    assert SkillLink.manual.exists?(from_node: "survey-the-roof-and-site", to_node: "price-the-roofing-job")
    assert_equal "interconnect-the-solar-array", @job.situation_specs.find { |x| x["key"] == "solar-array" }["branch"]
    assert_includes Waypoint.find_by!(key: "junction:permit-the-roofing-job").body, "solar array"
    assert_includes Waypoint.find_by!(key: "junction:price-the-roofing-job").body, "insurance claim"

    s = @sheets.install!(user: @admin)
    assert_equal [5, 33], [s.created.size, s.commands]
    assert_equal({ "unverified" => 33 }, FormulaCommand.where(provider: "jobcost").group(:status).count,
                 "nobody here has checked these rates yet")
    assert_equal "=ROUND({area}/100,2)", FormulaCommand.find_by!(provider: "jobcost", key: "squares").syntax
  end

  test "every worksheet in the pack plans cleanly in the add-in's builder" do
    @sheets.install!(user: @admin)
    commands = FormulaCommand.where(provider: "jobcost").to_h { |c| [c.key, c.to_builder] }
    blueprints = Skill.published.where(domain: "jobcost").to_h { |sk| [sk.name, sk.source["worksheet"]] }
    script = <<~JS
      const { plan } = await import("#{Rails.root.join('app/javascript/addin/worksheet_builder.js')}");
      const commands = #{commands.to_json}, bps = #{blueprints.to_json};
      const out = {};
      for (const [name, bp] of Object.entries(bps)) {
        const src = bp.source ? { [bp.source]: bps[bp.source] } : {};
        const p = plan(bp, { commands, sources: src });
        out[name] = { warnings: p.warnings, cells: (p.cells || []).length, charts: (p.charts || []).length,
                      sample: (p.cells || []).filter((c) => c.formula).slice(0, 2).map((c) => c.formula) };
      }
      console.log(JSON.stringify(out));
    JS
    File.write(Rails.root.join("tmp/plan_jobcost.mjs"), script)
    json = `cd #{Rails.root} && node --input-type=module -e #{Shellwords.escape(script)} 2>&1`
    assert_match(/^\{/, json, json)
    out = JSON.parse(json[/\{.*\}/m])
    out.each { |name, p| assert_empty p["warnings"], "#{name}: #{p['warnings'].inspect}" }
    assert_operator out["jobcost-estimate-summary"]["cells"], :>, 40
    assert_match(/ROUND\(/, out["jobcost-estimate-summary"]["sample"].first)
    assert_equal 1, out["jobcost-estimate-chart"]["charts"]
    assert_operator out["jobcost-margin-sensitivity"]["cells"], :>, 25
  end

  test "a job carries its jacket: documents, figures and the checks each leg has to pass" do
    @job.install!(user: @admin)
    run = @pm.playbook_runs.create!(playbook_key: "roofing-solar", reference: "J-2041")
    legs = Capture::Legs.new(run)
    legs.verify_all!
    refute_equal "verified", run.reload.legs.dig("qualify-the-roofing-lead", "status"), "nothing is verified before the work is done"

    run.update!(inputs: run.inputs.merge("job_number" => "J-2041", "job_type" => "Commercial re-roof",
                                         "burdened_labour_rate" => "44", "estimated_cost" => "112000",
                                         "target_margin_pct" => "22", "lien_deadline_days" => "90"))
    attest = ->(leg, key) do
      st = run.legs[leg] || {}
      run.update!(legs: run.legs.merge(leg => st.merge("attested" => (st["attested"] || {}).merge(key => { "by" => @pm.id, "at" => Time.current.iso8601 }))))
    end
    run.answers = { "solar-array" => "no", "insurance-claim" => "no", "commercial-rfp" => "yes", "subcontracted-work" => "yes",
                       "hidden-damage" => "yes", "prevailing-wage" => "no", "maintenance-agreement" => "no", "collections" => "no" }
    attest.("qualify-the-roofing-lead", "decision_maker")
    Capture::Legs.new(run).verify_all!
    assert_equal "verified", run.reload.legs.dig("qualify-the-roofing-lead", "status")

    # the route picked up the branches the job said yes to
    names = run.route.map { |x| x[:name] }
    assert_includes names, "answer-the-commercial-bid"
    assert_includes names, "manage-the-subcontractors"
    refute_includes names, "interconnect-the-solar-array"

    # figures come off the documents, and the billing check compares them
    doc = ->(kind, fields) do
      d = run.documents.new(kind: kind, content_type: "application/pdf", content: Base64.strict_encode64("pdf #{SecureRandom.hex}"),
                            byte_size: 10, checksum: SecureRandom.hex, filename: "#{kind}.pdf", status: "confirmed", read_by: "manual")
      d.assign_fields(fields, run.playbook.catalog)
      d.label = kind.titleize
      d.save!
      d
    end
    doc.("signed-contract", { "signed" => "yes", "signed_date" => "2026-03-02", "contract_value" => "146000", "retainage_pct" => "10" })
    doc.("measurement-report", { "squares" => "312", "layers" => "1", "deck_concern" => "yes" })
    doc.("pay-application", { "completed_to_date" => "97700", "retainage" => "9770", "previous_payments" => "34830", "amount_due" => "53100" })
    doc.("change-order", { "signed" => "yes", "amount" => "7400", "reason" => "Wet insulation, 1,100 sq ft" })
    doc.("lien-waiver", { "waiver_type" => "conditional progress", "amount" => "53100", "from_party" => "us" })
    attest.("bill-the-roofing-job", "quantities")
    legs = Capture::Legs.new(run.reload)
    legs.verify_all!
    bill = run.reload.legs["bill-the-roofing-job"]
    shown = bill["figures"]
    assert_equal 153_400.0, shown["contract_to_date"], "contract plus the signed change order"
    assert_equal 97_700.0, shown["completed_to_date"]
    assert_equal 87_930.0, shown["billed_net"], "completed less retainage"
    assert bill["checks"].find { |c| c["label"].to_s.start_with?("Billed no more") }["ok"], "billed within the contract"

    # over-billing is caught
    run.documents.find_by(kind: "pay-application").then { |d| d.assign_fields({ "completed_to_date" => "171000", "retainage" => "17100", "previous_payments" => "34830" }, run.playbook.catalog); d.save! }
    Capture::Legs.new(run.reload).verify_all!
    over = run.reload.legs["bill-the-roofing-job"]
    refute over["checks"].find { |c| c["label"].to_s.start_with?("Billed no more") }["ok"], "billed past the contract is caught"
  end

  test "the console shows the sphere: the job route, its library and the job costing formulas" do
    @job.install!(user: @admin)
    @sheets.install!(user: @admin)
    sign_in @pm
    get playbook_path("roofing-solar")
    assert_select "h1", text: /Roofing and solar job/
    assert_select "a", text: "Survey the roof and the site"
    get skills_path(domain: "field-services")
    assert_select "a", text: "Bill the job"
    get formulas_path(provider: "jobcost")
    assert_select "code", text: "retainage"
    assert_select "div", text: /Retainage withheld at the contract rate/
    get skill_path(Skill.current("jobcost-pay-application"))
    assert_select "#worksheet", text: /Pay application/
  end
end
