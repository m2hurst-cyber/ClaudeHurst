require "test_helper"

class PricingUiTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = make_user(role: "admin", name: "Ada")
    @member = make_user(role: "member", name: "Mo")
    @skill = Capture::Publisher.publish!(drafted_candidate(name: "close-books"), reviewer: @admin)
    SkillMetric.create!(name: "close-books", trips: 8, people: 3, median_minutes: 30, freeflow_minutes: 10,
                        congestion_index: 3.0, tier: "jammed", price: 40, delay_hours: 2.7)
    Bounty.create!(skill_name: "close-books", pool: 120, opened_index: 3.0, accrued_until: Time.current)
  end

  test "everyone sees bounties, the skill's traffic, and can propose a fix" do
    sign_in @member
    get bounties_path
    assert_response :success
    assert_includes response.body, "120 credits"
    assert_includes response.body, "Jammed"
    assert_includes response.body, %(href="/skill_candidates/new?fix=close-books")

    get skill_path(@skill)
    assert_includes response.body, "Traffic &amp; price"
    assert_includes response.body, "40 credits"

    get new_skill_candidate_path(fix: "close-books")
    assert_includes response.body, "Propose a faster way"
    post skill_candidates_path, params: { skill_candidate: { draft_title: "Bill a new order", domain: "finance", draft_body: "faster", fix: "close-books" } }
    c = SkillCandidate.order(:id).last
    assert_equal ["close-books", @member], [c.draft_name, c.requested_by]
  end

  test "map shows traffic data and the route planner returns it" do
    sign_in @member
    get skill_map_path
    data = JSON.parse(response.body[%r{data-route-map-target="data">(.*?)</script>}m, 1])
    node = data["nodes"].find { |n| n["id"] == "close-books" }
    assert_equal ["jammed", 40.0, { "status" => "open", "pool" => 120.0 }], node.values_at("tier", "price", "bounty")
    assert_includes response.body, %(data-mode="traffic")
  end

  test "admins edit the demand schedule; invalid schedules are refused; members can't" do
    sign_in @member
    get admin_pricing_path
    assert_redirected_to root_path
    sign_out @member

    sign_in @admin
    get admin_pricing_path
    assert_response :success
    assert_includes response.body, "Price per trip by congestion"
    tiers = [{ label: "Clear", min_index: 0, multiplier: 1 }, { label: "Busy", min_index: 1.5, multiplier: 2 }, { label: "Gridlock", min_index: 2.5, multiplier: 5 }]
    patch admin_pricing_path, params: { pricing_schedule: { base_price: 20, currency: "points", bounty_tier: "busy", tiers: tiers } }
    s = PricingSchedule.current.reload
    assert_equal ["points", 20, %w[clear busy gridlock]], [s.currency, s.base_price.to_i, s.sorted_tiers.map { |t| t["key"] }]
    assert_equal 100, s.price_for(3).to_i

    patch admin_pricing_path, params: { pricing_schedule: { tiers: [{ label: "Only", min_index: 0, multiplier: 1 }] } }
    assert_response :unprocessable_entity
  end

  test "agents see price and bounty on the skills API" do
    _, token = make_source
    get api_v1_skills_path, headers: { "Authorization" => "Bearer #{token}" }
    t = response.parsed_body.first["traffic"]
    assert_equal ["jammed", 40.0, 120.0], t.values_at("tier", "price", "bounty_pool")
  end
end
