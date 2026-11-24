require "test_helper"

# Skills at every level: mine, my department, the firm, our industry, global.
class LevelsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    PromotionPolicy.current.update!(initial_stage: "firm")
    @admin = make_user(role: "admin", name: "Ada Admin")
    @rae = make_user(role: "member", domains: %w[finance], name: "Rae")
    @dee = make_user(role: "member", domains: %w[legal], name: "Dee")
    @out = make_user(role: "member", domains: %w[legal], name: "Out")
    [[@rae, "Equity research"], [@dee, "Equity research"], [@out, "Legal ops"]].each { |u, d| u.update!(department: d) }
    @mine = publish("rae-skill", @rae)
    @dees = publish("dee-skill", @dee)
    @firm = publish("firm-skill", nil)
    @industry = publish("industry-skill", nil).tap { |s| s.update!(stage: "market", market_audience: "industry") }
    @global = publish("global-skill", nil).tap { |s| s.update!(stage: "market") }
  end

  def publish(name, requester)
    steps = ["x.#{name}:a", "x.#{name}:b"]
    c = SkillCandidate.create!(signature: SkillCandidate.signature_for(steps), steps: steps, domain: "finance", status: "drafted", requested_by: requester,
                               draft_name: name, draft_title: name.titleize, draft_description: "Does #{name}.", draft_body: "1. a\n2. b")
    Capture::Publisher.publish!(c, reviewer: @admin)
  end

  def names(level, user) = Skill.published.at_level(level, user).pluck(:name).sort

  test "each level selects the right skills" do
    assert_equal %w[rae-skill], names("mine", @rae)
    assert_equal %w[dee-skill rae-skill], names("department", @rae)
    assert_equal %w[dee-skill firm-skill rae-skill], names("firm", @rae)
    assert_equal %w[industry-skill], names("industry", @rae)
    assert_equal %w[global-skill], names("global", @rae)
    assert_includes @out.department_colleagues, @out
    refute_includes @out.department_colleagues, @rae
    @rae.update!(department: nil)
    assert_includes @rae.department_colleagues.map(&:name), "Rae", "no department: colleagues are people in the same areas"
  end

  test "library chips, add-in API and map carry the level" do
    sign_in @rae
    get skills_path(level: "department")
    assert_select "a", text: "Dee Skill"
    assert_select "a", text: "Firm Skill", count: 0
    assert_select "nav[aria-label=Level] a", text: "Department"

    token = AddinToken.issue!(user: @rae, host: "Excel").last
    get "/api/v1/addin/skills", params: { level: "mine" }, headers: { "Authorization" => "Bearer #{token}" }
    assert_equal %w[rae-skill], response.parsed_body.map { |s| s["name"] }

    get skill_map_path(format: :json)
    nodes = response.parsed_body["nodes"].index_by { |n| n["id"] || n["name"] }
    assert_includes nodes["rae-skill"]["levels"], "mine"
    assert_includes nodes["dee-skill"]["levels"], "department"
    assert_includes nodes["industry-skill"]["levels"], "industry"
    get skill_map_path
    assert_select "[data-route-map-target=levelChip]", minimum: 5
  end

  test "admins choose who a market skill is shared with" do
    sign_in @admin
    patch audience_skill_path(@global), params: { market_audience: "industry" }
    assert_equal "industry", @global.reload.market_audience
    sign_in @rae
    patch audience_skill_path(@industry), params: { market_audience: "global" }
    assert_equal "industry", @industry.reload.market_audience
  end
end
