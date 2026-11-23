require "test_helper"

class SkillMapTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @finance = make_user(role: "reviewer", domains: %w[finance], name: "Fin Reviewer")
    make_user(role: "reviewer", domains: %w[hr], name: "Hr Reviewer")
    @member = make_user(role: "member")
    Capture::Publisher.publish!(drafted_candidate(steps: %w[excel.data.sorted excel.formula.changed], name: "close-books"), reviewer: @finance)
    drafted_candidate(steps: %w[word.paragraph.changed word.paragraph.added], domain: "legal", name: "nda")
    SkillCandidate.create!(signature: "a.b>c.d", steps: %w[a.b c.d], status: "detected", domain: nil)
  end

  test "map summarizes each area with stages, reviewers, apps and gaps" do
    areas = Capture::SkillMap.call.index_by(&:name)
    assert_equal %w[finance legal hr unassigned], Capture::SkillMap.call.map(&:name)

    fin = areas["finance"]
    assert_equal [1, 0, 0], [fin.published, fin.awaiting_review, fin.detected]
    assert_equal ["Fin Reviewer"], fin.reviewers
    assert_equal({ "Excel" => 2 }, fin.apps)
    assert_empty fin.gaps

    legal = areas["legal"]
    assert_equal 1, legal.awaiting_review
    assert_includes legal.gaps, "No reviewer for this area"
    assert_includes legal.gaps, "Repeated work, nothing published yet"

    assert_equal 0, areas["hr"].total, "a reviewer's area shows even before any skills exist"
    assert_includes areas["unassigned"].gaps, "Needs an area so the right reviewer sees it"
  end

  test "any signed-in person sees the map page, chart, table and cards" do
    sign_in @member
    get skill_map_path
    assert_response :success
    body = response.body
    assert_includes body, "Skills by area"
    assert_includes body, 'aria-label="Finance: 1 published"'
    assert_includes body, ">HR<"
    assert_includes body, "Show as table"
    assert_includes body, "No reviewer for this area"
    assert_includes body, 'id="area-unassigned"'
    assert_includes body, 'href="/skills?domain=finance"', "area links must keep the filter (url helpers eat a domain: option)"

    get skill_map_path(format: :json)
    legal = response.parsed_body.find { |a| a["name"] == "legal" }
    assert_equal 1, legal["awaiting_review"]
  end

  test "the add-in gets areas that have published skills" do
    token = AddinToken.issue!(user: @member).last
    get api_v1_addin_areas_path, headers: { "Authorization" => "Bearer #{token}" }
    assert_equal [{ "name" => "finance", "published" => 1 }], response.parsed_body
    get api_v1_addin_skills_path, params: { domain: "legal" }, headers: { "Authorization" => "Bearer #{token}" }
    assert_empty response.parsed_body
    get api_v1_addin_skills_path, params: { domain: "finance" }, headers: { "Authorization" => "Bearer #{token}" }
    assert_equal ["close-books"], response.parsed_body.map { |s| s["name"] }
  end
end
