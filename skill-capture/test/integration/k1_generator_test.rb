require "test_helper"

# The K-1 generator: a partnership playbook whose last step generates each partner's K-1 and
# hands it off into the partner's individual return, where the K-1 branch picks it up.
class K1GeneratorTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    Capture::Taxonomy.ensure_defaults!
    @admin = make_user(role: "admin", name: "Ada Admin")
    @filer = make_user(role: "reviewer", domains: %w[tax], name: "Pat Preparer")
    Capture::Playbook.find("individual-income-tax").install!(user: @admin)
    Capture::Playbook.find("partnership-k1s").install!(user: @admin)
    @partnership = @filer.playbook_runs.create!(playbook_key: "partnership-k1s", reference: "P-2026-07", inputs: { "tax_year" => "2025" })
    @individual = @filer.playbook_runs.create!(playbook_key: "individual-income-tax", reference: "2026-0142")
  end

  def doc!(run, kind, fields)
    d = run.documents.new(kind: kind, content_type: "application/pdf", content: Base64.strict_encode64("x#{SecureRandom.hex}"), byte_size: 1,
                          checksum: SecureRandom.hex, filename: "#{kind}.pdf", tax_year: 2025, status: "confirmed", read_by: "manual")
    d.assign_fields(fields, run.playbook.catalog)
    d.label = Capture::ReturnDocuments.label_for(d)
    d.save!
    d
  end

  test "the generator skill is installed, linked into the individual return's K-1 branch, with handoff directions at the intersection" do
    gen = Skill.current("generate-schedule-k1s")
    assert_equal ["tax", "firm", "partnership-k1s"], [gen.domain, gen.stage, gen.source["playbook"]]
    assert Capture::SkillStandard.check_skill(gen).clean?
    assert SkillLink.manual.exists?(from_node: "allocate-partnership-items", to_node: "generate-schedule-k1s")
    assert SkillLink.manual.exists?(from_node: "generate-schedule-k1s", to_node: "report-k1-pass-through-income"), "the road crosses into the individual return"
    handoff = Waypoint.find_by!(key: "handoff:generate-schedule-k1s>report-k1-pass-through-income")
    assert_includes handoff.body, "What crosses: one K-1 statement per partner"
    junction = Waypoint.find_by!(key: "junction:generate-schedule-k1s").body
    assert_includes junction, "Hands off to another road"
    assert_includes junction, "Report K-1 pass-through income"

    map = Capture::RouteMap.new(@filer).call
    edge = map[:edges].find { |e| e[:from] == "generate-schedule-k1s" && e[:to] == "report-k1-pass-through-income" }
    assert edge
    assert_equal ["Partnership tax", "Individual income tax"], edge.dig(:bridge, :fields), "it's a bridge between the two tax roads"
    get api_v1_place_path("handoff:generate-schedule-k1s>report-k1-pass-through-income"), headers: { "Authorization" => "Bearer #{make_source.last}" }
    assert_equal "handoff", response.parsed_body["kind"]
  end

  test "K-1s split the 1065 by profit share to the cent, tie back on every line, and the leg verifies" do
    doc!(@partnership, "form-1065-summary", { ordinary_income: 100_000.01, rental_income: -2_000, interest: 333.33, dividends: 1_000, distributions: 45_000 })
    doc!(@partnership, "partner", { partner_ref: "PTR-A", profit_pct: 33.34, capital_pct: 40, distributions: 15_000 })
    doc!(@partnership, "partner", { partner_ref: "PTR-B", profit_pct: 33.33, capital_pct: 30, distributions: 15_000 })
    c = doc!(@partnership, "partner", { partner_ref: "PTR-C", profit_pct: 30, capital_pct: 30, distributions: 15_000 })
    sign_in @filer
    post generate_playbook_run_path(@partnership)
    assert_match(/add up to 96.67%, not 100%/, flash[:alert])

    c.assign_fields({ partner_ref: "PTR-C", profit_pct: 33.33, capital_pct: 30, distributions: 15_000 }, @partnership.playbook.catalog)
    c.save!
    post generate_playbook_run_path(@partnership)
    assert_match(/Generated 3 K-1s/, flash[:notice])
    k1s = Capture::K1Generator.generated(@partnership.reload)
    by = k1s.index_by { |k| k.fields["partner_ref"] }
    assert_equal [33_340.01, 33_330.0, 33_330.0], %w[PTR-A PTR-B PTR-C].map { |r| by[r].fields["ordinary_income"] }, "the leftover cent goes to the largest remainder"
    assert_in_delta 100_000.01, k1s.sum { |k| k.fields["ordinary_income"] }, 0.001
    assert_in_delta(-2_000, k1s.sum { |k| k.fields["rental_income"] }, 0.001)
    assert_in_delta 333.33, k1s.sum { |k| k.fields["interest"] }, 0.001
    pdf = by["PTR-A"].bytes
    assert pdf.start_with?("%PDF-1.4")
    assert_includes pdf, "Partner: PTR-A - profit share 33.34%"

    legs = @partnership.reload.legs
    assert_equal [], legs.dig("generate-schedule-k1s", "checks").reject { |x| x["ok"] }.map { |x| x["label"] } - ["Every partner's K-1 is delivered (to their return or through the secure portal)"]
    post attest_playbook_run_path(@partnership), params: { leg: "generate-schedule-k1s", key: "delivered", value: "1" }
    assert @partnership.reload.verified?("generate-schedule-k1s")
    post generate_playbook_run_path(@partnership)
    assert_equal 3, Capture::K1Generator.generated(@partnership.reload).size, "regenerating replaces the set"
  end

  test "the handoff: a generated K-1 lands in the partner's individual return, turning on its K-1 branch" do
    doc!(@partnership, "form-1065-summary", { ordinary_income: 60_000, distributions: 20_000 })
    doc!(@partnership, "partner", { partner_ref: "PTR-A", profit_pct: 50, capital_pct: 50, distributions: 10_000 })
    doc!(@partnership, "partner", { partner_ref: "PTR-B", profit_pct: 50, capital_pct: 50, distributions: 10_000 })
    k1 = Capture::K1Generator.generate!(@partnership, user: @filer).first
    assert_not @individual.route.any? { |x| x[:name] == "report-k1-pass-through-income" }

    sign_in @filer
    post deliver_playbook_run_path(@partnership), params: { document_id: k1.id, target_id: @individual.id }
    assert_match(/Sent K-1 PTR-A to return 2026-0142 as K-1 #1/, flash[:notice])
    got = @individual.reload.documents.sole
    assert_equal ["k-1", "read", "handoff", 30_000.0, 10_000.0], [got.kind, got.status, got.read_by, got.fields["ordinary_income"], got.fields["distributions"]]
    assert_nil got.fields["partner_ref"]
    assert_equal "yes", @individual.answers["k1-income"]
    assert @individual.route.any? { |x| x[:name] == "report-k1-pass-through-income" }, "the K-1 branch is now on the road"
    assert_equal "2026-0142", @partnership.reload.leg("generate-schedule-k1s").dig("delivered", k1.id.to_s, "reference")

    post deliver_playbook_run_path(@partnership), params: { document_id: k1.id, target_id: @individual.id }
    assert_match(/already has this K-1/, flash[:alert])
    someone = make_user(role: "member", domains: %w[tax]).playbook_runs.create!(playbook_key: "individual-income-tax", reference: "X-1")
    post deliver_playbook_run_path(@partnership), params: { document_id: k1.id, target_id: someone.id }
    assert_response :not_found

    get playbook_run_path(@partnership)
    assert_includes response.body, "→ return 2026-0142"
    get playbook_run_path(@individual)
    assert_includes response.body, "Sent from the K-1 generator on partnership return P-2026-07"
  end
end
