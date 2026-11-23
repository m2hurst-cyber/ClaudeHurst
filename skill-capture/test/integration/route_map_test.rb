require "test_helper"

# The route map: skills as roads, journeys between them, branches and improvements.
class RouteMapTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  INVOICE = %w[erp.receive:invoice erp.match:po].freeze
  APPROVE = %w[outlook.send:approval erp.approve:invoice].freeze
  PAY     = %w[bank.create:payment bank.release:payment].freeze

  setup do
    @source, @integration_token = make_source
    @reviewer = make_user(role: "reviewer", domains: %w[finance], name: "Fin")
    @member = make_user(role: "member")
    @receive = publish("receive-invoice", INVOICE)
    @approve = publish("approve-invoice", APPROVE)
    @pay = publish("pay-vendor", PAY)
  end

  def publish(name, steps, domain: "finance")
    c = SkillCandidate.create!(signature: SkillCandidate.signature_for(steps), steps: steps, domain: domain, status: "drafted",
                               draft_name: name, draft_title: name.tr("-", " ").capitalize, draft_description: "d", draft_body: "b")
    Capture::Publisher.publish!(c, reviewer: @reviewer)
  end

  # People doing receive → approve → pay, end to end.
  def journeys(n, chain, start: 5.days.ago, gap: 2.hours)
    n.times do |i|
      t = start + i.hours * 10
      chain.each_with_index do |steps, j|
        perform_workflow(@source, "person-#{i}", steps, start: t + j * gap)
      end
    end
  end

  test "observed journeys become roads with traffic; one-offs and long gaps don't" do
    journeys(3, [INVOICE, APPROVE, PAY])
    journeys(1, [INVOICE, PAY], start: 2.days.ago)              # below min traffic of 2
    journeys(2, [APPROVE, INVOICE], start: 1.day.ago, gap: 3.days) # too far apart

    counts = Capture::ChainDetector.call
    assert_equal 3, counts[%w[receive-invoice approve-invoice]]
    assert_equal 3, counts[%w[approve-invoice pay-vendor]]
    links = SkillLink.observed.pluck(:from_node, :to_node, :traffic)
    assert_equal [["approve-invoice", "pay-vendor", 3], ["receive-invoice", "approve-invoice", 3]], links.sort
  end

  test "recomputing replaces observed roads but keeps reviewers' links" do
    SkillLink.create!(from_node: "pay-vendor", to_node: "receive-invoice", origin: "manual")
    journeys(2, [INVOICE, APPROVE])
    Capture::ChainDetector.call
    UsageEvent.delete_all
    Capture::ChainDetector.call
    assert_empty SkillLink.observed
    assert_equal 1, SkillLink.manual.count
  end

  test "the map shows roads, branches, improvements and unpaved workflows (only to people allowed to see them)" do
    journeys(2, [INVOICE, APPROVE])
    Capture::ChainDetector.call
    Capture::Publisher.revise!(@approve, editor: @reviewer, attrs: { body: "Better" })            # improvement
    fork = Capture::Publisher.revise!(Skill.current("pay-vendor"), editor: @reviewer, attrs: { name: "pay-vendor-abroad" }) # branch
    unpaved = drafted_candidate(steps: %w[x.one y.two], name: "draft")

    map = Capture::RouteMap.call(user: @reviewer)
    nodes = map[:nodes].index_by { |n| n[:id] }
    assert_equal 1, nodes["approve-invoice"][:improvements]
    assert_equal "skill", nodes["pay-vendor-abroad"][:kind]
    assert_equal "unpaved", nodes["candidate:#{unpaved.id}"][:kind]
    assert_includes map[:edges], { from: "receive-invoice", to: "approve-invoice", kind: "next", traffic: 2, manual: false }
    assert_includes map[:edges], { from: "pay-vendor", to: fork.name, kind: "branch", traffic: 0, manual: false }

    member_ids = Capture::RouteMap.call(user: @member)[:nodes].map { |n| n[:id] }
    refute_includes member_ids, "candidate:#{unpaved.id}"
  end

  test "route planner gives turn-by-turn, prefers busier roads, and reports gaps" do
    journeys(3, [INVOICE, APPROVE, PAY])
    detour = publish("escalate-invoice", %w[teams.post:escalation erp.hold:invoice])
    journeys(2, [INVOICE, %w[teams.post:escalation erp.hold:invoice], PAY], start: 2.days.ago)
    Capture::ChainDetector.call

    r = Capture::RoutePlanner.call(from: "receive-invoice", to: "pay-vendor")
    assert_equal %w[receive-invoice approve-invoice pay-vendor], r.keys, "busier road wins between equal-length routes"
    assert_nil Capture::RoutePlanner.call(from: "pay-vendor", to: "receive-invoice")
    assert_equal [detour.name], Capture::RoutePlanner.call(from: detour.name, to: detour.name).keys

    sign_in @member
    get skill_map_route_path(from: "receive-invoice", to: "pay-vendor")
    assert_equal %w[receive-invoice approve-invoice pay-vendor], response.parsed_body["stops"].map { |s| s["id"] }
    get skill_map_route_path(from: "pay-vendor", to: "receive-invoice")
    assert_equal false, response.parsed_body["found"]
  end

  test "agents can ask for a route over the integration API" do
    journeys(2, [INVOICE, APPROVE])
    Capture::ChainDetector.call
    get api_v1_route_path, params: { from: "receive-invoice", to: "approve-invoice" }, headers: { "Authorization" => "Bearer #{@integration_token}" }
    assert_equal %w[receive-invoice approve-invoice], response.parsed_body["skills"]
    get api_v1_route_path, params: { from: "approve-invoice", to: "receive-invoice" }, headers: { "Authorization" => "Bearer #{@integration_token}" }
    assert_response :not_found
  end

  test "reviewers draw roads by hand; members can't" do
    sign_in @member
    post skill_links_path(@pay), params: { to: "receive-invoice" }
    assert_empty SkillLink.all
    sign_out @member

    sign_in @reviewer
    post skill_links_path(@pay), params: { to: "receive-invoice" }
    assert_equal [["pay-vendor", "receive-invoice", "manual"]], SkillLink.pluck(:from_node, :to_node, :origin)
    get skill_path(@pay)
    assert_includes response.body, "People continue with"
    assert_includes response.body, "Receive invoice"
    delete skill_link_path(@pay, "receive-invoice")
    assert_empty SkillLink.all
  end

  test "map page embeds the network and the add-in shows what comes next" do
    journeys(2, [INVOICE, APPROVE])
    Capture::ChainDetector.call
    sign_in @member
    get skill_map_path
    assert_response :success
    data = JSON.parse(response.body[%r{<script type="application/json" data-route-map-target="data">(.*?)</script>}m, 1])
    assert_equal 3, data["nodes"].size
    assert_includes response.body, "Show as list"

    token = AddinToken.issue!(user: @member).last
    get api_v1_addin_skill_path("receive-invoice"), headers: { "Authorization" => "Bearer #{token}" }
    assert_equal [{ "name" => "approve-invoice", "title" => "Approve invoice", "traffic" => 2 }], response.parsed_body["next_up"]
  end
end
