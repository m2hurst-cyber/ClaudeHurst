require "test_helper"

# Field hierarchy + apps on every skill: inferred by AI (or rules), set by people, filterable everywhere.
class ClassificationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    Capture::Taxonomy.ensure_defaults!
    @rev = make_user(role: "reviewer", domains: %w[finance], name: "Rae")
    @member = make_user(role: "member", name: "Mo")
    @admin = make_user(role: "admin", name: "Ada")
    @recon = publish("reconcile-bank", "Reconcile the bank statement", %w[excel.import:bank excel.match:lines], "finance",
                     "Match every bank line to the ledger at month end.")
    @deck = publish("kpi-deck", "Build the KPI deck", %w[powerpoint.update:kpi_slides powerpoint.add:commentary], "sales",
                    "Update the KPI slide template with this month's charts.")
    _, @token = make_source
  end

  def publish(name, title, steps, domain, desc)
    c = SkillCandidate.create!(signature: SkillCandidate.signature_for(steps), steps: steps, domain: domain, status: "drafted",
                               draft_name: name, draft_title: title, draft_description: desc, draft_body: "1. a\n2. b")
    Capture::Publisher.publish!(c, reviewer: @admin)
  end

  test "taxonomy: default tree with paths; renaming or moving a branch re-paths everything below it" do
    finance = Field.find_by!(path: "finance")
    recon = Field.find_by!(path: "finance/accounting/reconciliation")
    assert_equal "Finance › Accounting › Reconciliation", recon.label
    finance.update!(name: "Finance & Accounting")
    assert_equal "finance-accounting/accounting/reconciliation", recon.reload.path
    data = Field.find_by!(path: "data-analysis")
    Field.find_by!(path: "finance-accounting/accounting").update!(parent: data)
    assert_equal "data-analysis/accounting/reconciliation", recon.reload.path
  end

  test "publishing classifies automatically: field from the text, apps from the steps" do
    c = SkillClassification.for("reconcile-bank")
    assert_equal ["finance/accounting/reconciliation", ["Excel"], "rules", false], [c.field.path, c.apps, c.source, c.confirmed]
    assert_operator c.confidence, :>, 0.5
    assert_match(/reconcil/, c.rationale)
    deck = SkillClassification.for("kpi-deck")
    assert_equal ["PowerPoint"], deck.apps
    assert_includes %w[design/presentation-design data-analysis/reporting], deck.field.path
  end

  test "Claude picks only from the taxonomy (closed list), and its result is used" do
    fake = FakeClaude.new(field_paths: %w[data-analysis/statistics finance/accounting/reconciliation made-up/path], apps: ["Excel", "Power BI"],
                          confidence: 0.91, rationale: "Variance math")
    r = Capture::Classifier.call(@recon, client: fake)
    assert_equal [%w[data-analysis/statistics finance/accounting/reconciliation], %w[Excel Power\ BI], "ai", 0.91],
                 [r.fields.map(&:path), r.apps, r.source, r.confidence]
    enum = fake.req.dig(:output_config, :format, :schema, :properties, :field_paths, :items, :enum)
    assert_includes enum, "finance/accounting/reconciliation"
    sent = JSON.parse(fake.req[:messages].first[:content])
    assert_equal "Reconcile the bank statement", sent.dig("skill", "title")

    none = Capture::Classifier.call(@recon, client: FakeClaude.new(field_paths: [], apps: [], confidence: 0.2, rationale: "?"))
    assert_empty none.fields
    assert_equal ["Excel"], none.apps, "apps seen in the steps are always kept"
  end

  test "people win: a confirmed classification is never overwritten by inference" do
    sign_in @rev
    stats = Field.find_by!(path: "data-analysis/statistics")
    patch skill_classification_path(@recon), params: { add_field_id: stats.id, apps: ["Outlook"] }
    c = SkillClassification.for("reconcile-bank")
    assert_equal ["user", true, [stats], %w[Excel Outlook], @rev], [c.source, c.confirmed, c.ordered_fields, c.apps, c.updated_by]
    Capture::Classifier.apply!(@recon.reload)
    assert_equal [stats], c.reload.ordered_fields

    post reinfer_skill_classification_path(@recon)
    c.reload
    assert_equal ["finance/accounting/reconciliation", false], [c.ordered_fields.first.path, c.confirmed]
    post confirm_skill_classification_path(@recon)
    assert_equal [true, @rev], c.reload.values_at(:confirmed, :updated_by_id).then { |a, b| [a, User.find(b)] }
    assert AuditLog.exists?(action: "classification.confirmed")
  end

  test "a skill can have any number of fields, and people can create new fields and subfields while classifying" do
    sign_in @rev
    recon = Field.find_by!(path: "finance/accounting/reconciliation")
    treasury = Field.find_by!(path: "finance/treasury")
    stats = Field.find_by!(path: "data-analysis/statistics")
    patch skill_classification_path(@recon), params: { field_ids: [recon.id, treasury.id], add_field_id: stats.id,
                                                       new_field_name: "Intercompany", new_field_parent_id: treasury.id }
    c = SkillClassification.for("reconcile-bank")
    assert_equal %w[finance/accounting/reconciliation finance/treasury data-analysis/statistics finance/treasury/intercompany], c.field_paths
    hex = Field.find_by!(path: "finance/treasury/intercompany")
    assert_equal [@rev, "Intercompany"], [hex.created_by, hex.name]
    assert c.bridge?, "spans Finance and Data analysis"
    assert_equal recon, c.field, "the first field is the primary one"

    patch skill_classification_path(@recon), params: { field_ids: [stats.id] } # unticking removes the others
    assert_equal ["data-analysis/statistics"], c.reload.field_paths

    get skills_path(field: "data-analysis")
    assert_includes response.body, "Reconcile the bank statement"
  end

  test "only the area's reviewers, publisher, contributors and admins can change it" do
    sign_in @member
    patch skill_classification_path(@recon), params: { add_field_id: Field.first.id }
    assert_redirected_to root_path
    assert_not SkillClassification.for("reconcile-bank").confirmed
  end

  test "library filters by app and by field (including subfields); cards show both fields" do
    sign_in @member
    get skills_path(app: "PowerPoint")
    assert_includes response.body, "Build the KPI deck"
    refute_includes response.body, "Reconcile the bank statement"
    get skills_path(field: "finance")
    assert_includes response.body, "Reconcile the bank statement"
    refute_includes response.body, "Build the KPI deck"
    assert_includes response.body, "Finance › Accounting › Reconciliation"
    assert_includes response.body, "✨ Inferred"
  end

  test "map carries field, apps and the taxonomy; the By field view shows the hierarchy with filters" do
    sign_in @member
    get skill_map_path
    data = JSON.parse(response.body[%r{data-route-map-target="data">(.*?)</script>}m, 1])
    node = data["nodes"].find { |n| n["id"] == "reconcile-bank" }
    assert_equal ["finance/accounting/reconciliation", ["Excel"], "rules"], node.values_at("field", "apps", "classified_by")
    assert data["fields"].any? { |f| f["path"] == "finance/accounting" && f["parent"] == "finance" }
    assert_includes response.body, %(data-app="PowerPoint")

    get skill_map_fields_path
    assert_response :success
    assert_includes response.body, "Reconciliation"
    assert_includes response.body, "Reconcile the bank statement"
    get skill_map_fields_path(app: ["PowerPoint"])
    refute_includes response.body, "Reconcile the bank statement"
    assert_includes response.body, "Build the KPI deck"
  end

  test "agents filter by app and field and read the taxonomy; the add-in filters by its host app" do
    h = { "Authorization" => "Bearer #{@token}" }
    get api_v1_skills_path, params: { app: "Excel" }, headers: h
    assert_equal ["reconcile-bank"], response.parsed_body.map { |s| s["name"] }
    assert_equal "Finance › Accounting › Reconciliation", response.parsed_body.first["field_label"]
    get api_v1_skills_path, params: { field: "finance/accounting" }, headers: h
    assert_equal ["reconcile-bank"], response.parsed_body.map { |s| s["name"] }
    get api_v1_fields_path, headers: h
    assert response.parsed_body.any? { |f| f["label"] == "Data analysis › Statistics" }

    token = AddinToken.issue!(user: @member).last
    get api_v1_addin_skills_path, params: { app: "PowerPoint" }, headers: { "Authorization" => "Bearer #{token}" }
    assert_equal [["kpi-deck", ["PowerPoint"]]], response.parsed_body.map { |s| s.values_at("name", "apps") }
  end

  test "admins edit the taxonomy" do
    sign_in @admin
    get admin_fields_path
    assert_includes response.body, "finance/accounting/reconciliation"
    stats = Field.find_by!(path: "data-analysis/statistics")
    post admin_fields_path, params: { field: { name: "Hypothesis testing", parent_id: stats.id, keywords: "t-test, p-value" } }
    f = Field.find_by!(path: "data-analysis/statistics/hypothesis-testing")
    assert_equal %w[t-test p-value], f.keywords
    delete admin_field_path(stats)
    assert Field.exists?(stats.id), "can't remove a field that has subfields"
    delete admin_field_path(f)
    assert_not Field.exists?(f.id)
  end

  class FakeClaude
    attr_reader :req
    Msg = Struct.new(:stop_reason, :content)
    Block = Struct.new(:type, :text)
    def initialize(**json) = @json = json
    def beta = self
    def messages = self
    def create(**req)
      @req = req
      Msg.new(:end_turn, [Block.new(:text, @json.to_json)])
    end
  end
end
