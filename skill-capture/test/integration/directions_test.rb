require "test_helper"

# Roads, intersections and handoffs: searchable, each with its own agent directions.
class DirectionsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @reviewer = make_user(role: "reviewer", domains: %w[finance], name: "Rae")
    @legal = make_user(role: "reviewer", domains: %w[legal], name: "Lee")
    @member = make_user(role: "member", name: "Mo")
    @export = publish("export-trial-balance", "Export the trial balance", %w[erp.export:tb erp.save:tb])
    @recon = publish("reconcile-bank", "Reconcile the bank statement", %w[excel.import:bank excel.match:lines])
    @fx = publish("reconcile-fx-bank", "Reconcile a multi-currency account", %w[excel.import:fx excel.revalue:fx])
    SkillLink.create!(from_node: "export-trial-balance", to_node: "reconcile-bank", origin: "observed", traffic: 6)
    SkillLink.create!(from_node: "export-trial-balance", to_node: "reconcile-fx-bank", origin: "observed", traffic: 2)
    _, @token = make_source
  end

  def publish(name, title, steps)
    c = SkillCandidate.create!(signature: SkillCandidate.signature_for(steps), steps: steps, domain: "finance", status: "drafted",
                               draft_name: name, draft_title: title, draft_description: "#{title}.", draft_body: "# #{title}", draft_outputs: ["#{title} done"])
    Capture::Publisher.publish!(c, reviewer: @reviewer)
  end

  def api(path, params = {}) = get(path, params: params, headers: { "Authorization" => "Bearer #{@token}" })

  test "unwritten places get directions generated from live data" do
    junction = Capture::Directions.find("junction:export-trial-balance")
    assert_not junction.written
    assert_equal "Intersection after Export the trial balance", junction.title
    assert_match(/1\. \*\*Reconcile the bank statement\*\* \(`reconcile-bank`\): 75% of trips/, junction.body)
    assert_match(/Default: take the most-travelled exit \(\*\*Reconcile the bank statement\*\*\)/, junction.body)
    assert_match(/ask a reviewer for finance: Rae/, junction.body)

    road = Capture::Directions.find("road:reconcile-bank")
    assert_match(/Usually reached after: \*\*Export the trial balance\*\*/, road.body)
    assert_match(/Done when\n- Reconcile the bank statement done/, road.body)

    handoff = Capture::Directions.find("handoff:export-trial-balance>reconcile-bank")
    assert_match(/Taken 6 times recently/, handoff.body)

    assert_raises(Capture::Directions::NotFound) { Capture::Directions.find("handoff:reconcile-bank>export-trial-balance") }
    assert_raises(Capture::Directions::NotFound) { Capture::Directions.find("road:nope") }
    assert_raises(Capture::Directions::NotFound) { Capture::Directions.find("bogus") }
  end

  test "area reviewers write directions (versioned); others can only read" do
    sign_in @member
    get place_path("junction:export-trial-balance")
    assert_response :success
    assert_includes response.body, "Generated from live data"
    refute_includes response.body, "Write directions"
    get edit_place_path("junction:export-trial-balance")
    assert_redirected_to root_path
    sign_out @member

    sign_in @reviewer
    rule = "# After the trial balance\n\n- If the account holds foreign currency, take **Reconcile a multi-currency account**.\n- Otherwise take **Reconcile the bank statement**."
    patch place_path("junction:export-trial-balance"), params: { place: { body: rule, tags: "fx, Month End", note: "Added FX rule" } }
    assert_redirected_to place_path("junction:export-trial-balance")
    wp = Waypoint.find_by!(key: "junction:export-trial-balance")
    assert_equal [1, %w[fx month-end], "junction", "export-trial-balance"], [wp.version, wp.tags, wp.kind, wp.from_name]
    patch place_path("junction:export-trial-balance"), params: { place: { body: rule + "\n- Ask Rae if unsure." } }
    assert_equal [2, 2], [wp.reload.version, wp.revisions.count]
    assert AuditLog.exists?(action: "directions.saved", subject: wp)

    get place_path("junction:export-trial-balance", format: :md)
    assert_equal "text/markdown", response.media_type
    assert_includes response.body, "If the account holds foreign currency"

    patch place_path("junction:export-trial-balance"), params: { place: { body: "  " } }
    assert_response :unprocessable_entity
    sign_out @reviewer

    sign_in @legal # not the area's reviewer
    patch place_path("road:reconcile-bank"), params: { place: { body: "x" } }
    assert_nil Waypoint.find_by(key: "road:reconcile-bank")
  end

  test "search finds roads, intersections, handoffs and words inside written directions" do
    Capture::Directions.save!(Capture::Directions.find("junction:export-trial-balance"), body: "If the ledger has foreign currency, take the multi-currency road.", user: @reviewer)
    hits = Capture::MapSearch.call("reconcile")
    kinds = hits.map(&:kind).uniq
    assert_equal %w[road handoff].sort, (kinds & %w[road handoff]).sort
    assert hits.any? { |h| h.key == "road:reconcile-bank" }
    assert hits.any? { |h| h.key == "handoff:export-trial-balance>reconcile-bank" }

    junction = Capture::MapSearch.call("trial balance").find { |h| h.kind == "junction" }
    assert_equal "junction:export-trial-balance", junction.key
    assert junction.written

    by_text = Capture::MapSearch.call("foreign currency")
    assert_equal "junction:export-trial-balance", by_text.first.key, "full-text match inside directions"
    assert_empty Capture::MapSearch.call("x")

    sign_in @member
    get map_search_path(q: "reconcile", format: :json)
    assert response.parsed_body.any? { |h| h["label"] == "Handoff" && h["url"].start_with?("/map/places/") }
    get map_search_path(q: "reconcile")
    assert_includes response.body, "Reconcile the bank statement"
  end

  test "agents search the map, read any place as Markdown, and get directions with routes" do
    api api_v1_search_path, q: "multi-currency"
    assert_includes response.parsed_body.map { |h| h["key"] }, "road:reconcile-fx-bank"

    api api_v1_place_path("junction:export-trial-balance", format: :md)
    assert_equal "text/markdown", response.media_type
    assert_match(/^# Intersection after Export the trial balance/, response.body)
    api api_v1_place_path("road:missing")
    assert_response :not_found

    api api_v1_route_path, from: "export-trial-balance", to: "reconcile-bank"
    d = response.parsed_body["directions"]
    assert_equal %w[road junction handoff road], d.map { |x| x["kind"] }
    assert_equal "handoff:export-trial-balance>reconcile-bank", d[2]["key"]
    assert d.all? { |x| x["markdown"].present? }
  end

  test "the map embeds which places have written directions; the add-in shows the intersection" do
    Capture::Directions.save!(Capture::Directions.find("junction:export-trial-balance"), body: "Take the FX road for foreign currency.", user: @reviewer)
    sign_in @member
    get skill_map_path
    data = JSON.parse(response.body[%r{data-route-map-target="data">(.*?)</script>}m, 1])
    assert_equal ["junction:export-trial-balance"], data["written"]
    assert_includes response.body, %(placeholder="Search roads, intersections and handoffs)

    token = AddinToken.issue!(user: @member).last
    get api_v1_addin_skill_path("export-trial-balance"), headers: { "Authorization" => "Bearer #{token}" }
    j = response.parsed_body["junction"]
    assert_equal [true, "Take the FX road for foreign currency."], j.values_at("written", "markdown")
  end
end
