require "test_helper"

# Sandbox → firm → market, with gates, approvals and an internal vote on which process is better.
class GatekeepingTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  STEPS = %w[excel.import:bank excel.match:lines excel.flag:unmatched].freeze

  setup do
    PromotionPolicy.current.update!(initial_stage: "local")
    @source, @token = make_source
    @author = make_user(role: "member", domains: %w[finance], name: "Ana Author")      # recorded it
    @teammate = make_user(role: "member", domains: %w[finance], name: "Tim Teammate")
    @rev = make_user(role: "reviewer", domains: %w[finance], name: "Rae Reviewer")    # publishes
    @rev2 = make_user(role: "reviewer", domains: %w[finance], name: "Ola Reviewer")   # approves
    @outsider = make_user(role: "member", domains: %w[sales], name: "Sam Sales")
    @admin = make_user(role: "admin", name: "Ada Admin")
    c = SkillCandidate.create!(signature: "procedure:x", steps: STEPS, origin: "manual", domain: "finance", status: "drafted",
                               draft_name: "reconcile-bank", draft_title: "Reconcile the bank statement",
                               draft_description: "Match every bank line to the ledger at month end, before posting accruals.",
                               draft_body: "1. Import\n2. Match\n3. Flag", draft_outputs: ["Reconciled account"], requested_by: @author,
                               contributors: [{ "key" => @author.actor_key, "name" => @author.name }])
    @skill = Capture::Publisher.publish!(c, reviewer: @rev)
  end

  def use_in_sandbox(people: 2, trips: 3)
    trips.times { |i| perform_workflow(@source, "user:#{[@author, @teammate][i % people].id}", STEPS, start: (i + 1).days.ago) }
  end

  def vote(user, value, skill = @skill) = Capture::Voting.cast!(user, skill, value)

  test "new skills start in the sandbox; versions keep their stage; branches start local" do
    assert_equal "local", @skill.stage
    @skill.update!(stage: "firm")
    v2 = Capture::Publisher.revise!(@skill, editor: @rev, attrs: { body: "1. a\n2. b" })
    assert_equal "firm", v2.stage
    fork = Capture::Publisher.revise!(v2, editor: @rev, attrs: { name: "reconcile-bank-fx" })
    assert_equal "local", fork.stage
  end

  test "local skills are visible only to their people, never to agents" do
    assert @skill.visible_to?(@author), "contributor"
    assert @skill.visible_to?(@teammate), "same area"
    assert @skill.visible_to?(@rev), "publisher / area reviewer"
    assert @skill.visible_to?(@admin)
    assert_not @skill.visible_to?(@outsider)
    assert_not @skill.visible_to?(nil)

    sign_in @outsider
    get skills_path
    refute_includes response.body, "Reconcile the bank statement"
    get skill_path(@skill)
    assert_redirected_to root_path
    get map_search_path(q: "reconcile", format: :json)
    assert_empty response.parsed_body
    sign_out @outsider

    get api_v1_skills_path, headers: { "Authorization" => "Bearer #{@token}" }
    assert_empty response.parsed_body
    get api_v1_place_path("road:reconcile-bank"), headers: { "Authorization" => "Bearer #{@token}" }
    assert_response :not_found

    sign_in @teammate
    get skills_path(stage: "local")
    assert_includes response.body, "Reconcile the bank statement"
  end

  test "local → firm: gates, then an area reviewer who didn't publish or ask approves" do
    p = Capture::Promotions.new(@author).request!(@skill, pitch: "We use it every month")
    assert_equal %w[local firm open], [p.from_stage, p.to_stage, p.status]
    assert Notification.exists?(user: @rev2, kind: "promotion")
    assert_raises(Capture::Promotions::Error) { Capture::Promotions.new(@teammate).request!(@skill) } # one open request at a time

    err = assert_raises(Capture::Promotions::Error) { Capture::Promotions.new(@rev2).approve!(p) }
    assert_match(/Used in the sandbox, Colleagues vote for it/, err.message)

    use_in_sandbox
    vote(@teammate, 1)
    vote(@rev2, 1)
    assert Capture::Gates.passed?(Capture::Gates.for(@skill, "firm"))

    assert_raises(Capture::Promotions::Error) { Capture::Promotions.new(@author).approve!(p) }     # requester
    assert_raises(Capture::Promotions::Error) { Capture::Promotions.new(@rev).approve!(p) }        # publisher
    assert_raises(Capture::Promotions::Error) { Capture::Promotions.new(@outsider).approve!(p) }   # not a reviewer
    Capture::Promotions.new(@rev2).approve!(p, notes: "Solid")
    assert_equal ["firm", "approved", false], [@skill.reload.stage, p.reload.status, p.waived]
    assert p.checks.all? { |c| c["passed"] }
    assert Notification.exists?(user: @author, kind: "stage")

    assert @skill.visible_to?(@outsider)
    get api_v1_skills_path, headers: { "Authorization" => "Bearer #{@token}" }
    assert_equal [["reconcile-bank", "firm"]], response.parsed_body.map { |s| s.values_at("name", "stage") }
  end

  test "only admins waive failed gates, and only with a reason" do
    p = Capture::Promotions.new(@author).request!(@skill)
    assert_raises(Capture::Promotions::Error) { Capture::Promotions.new(@rev2).approve!(p, waive: true, notes: "urgent") }
    err = assert_raises(Capture::Promotions::Error) { Capture::Promotions.new(@admin).approve!(p, waive: true) }
    assert_match(/Explain why/, err.message)
    Capture::Promotions.new(@admin).approve!(p, waive: true, notes: "Needed for the audit this week")
    assert p.reload.waived
    assert AuditLog.exists?(action: "promotion.approved", subject: p)
  end

  test "firm → market needs time at firm, strong support, smooth traffic, a shareable license, directions, and an admin" do
    @skill.update!(stage: "firm", stage_changed_at: 20.days.ago)
    p = Capture::Promotions.new(@rev).request!(@skill)
    assert_equal "market", p.to_stage
    failing = Capture::Gates.for(@skill, "market").reject(&:passed).map(&:key)
    assert_equal %w[votes traffic license directions], failing

    5.times { |i| vote(make_user(role: "member", name: "Voter #{i}"), 1) }
    SkillMetric.create!(name: "reconcile-bank", trips: 9, congestion_index: 1.1, tier: "free", price: 10, median_minutes: 12, freeflow_minutes: 11)
    @skill.update!(license: "CC-BY-4.0")
    Capture::Directions.save!(Capture::Directions.find("road:reconcile-bank"), body: "# Road\nUse the bank export.", user: @rev)
    assert Capture::Gates.passed?(Capture::Gates.for(@skill, "market"))

    assert_raises(Capture::Promotions::Error) { Capture::Promotions.new(@rev2).approve!(p) } # reviewers can't
    Capture::Promotions.new(@admin).approve!(p)
    assert_equal "market", @skill.reload.stage

    get api_v1_market_path, headers: { "Authorization" => "Bearer #{@token}" }
    m = response.parsed_body.sole
    assert_equal "reconcile-bank", m["name"]
    assert_includes m["skill_md"], "name: reconcile-bank"
    assert_includes m["directions"], "Use the bank export"
  end

  test "voting: one vote per person, not on your own skill, changeable" do
    err = assert_raises(Capture::Voting::Error) { vote(@author, 1) }
    assert_match(/contributed/, err.message)
    assert_raises(Capture::Voting::Error) { vote(@rev, 1) } # publisher
    assert_raises(Capture::Voting::Error) { vote(@outsider, 1) } # can't see it

    vote(@teammate, 1)
    vote(@teammate, -1)
    vote(@rev2, 1)
    assert_equal({ score: 0, up: 1, down: 1 }, SkillVote.tallies(["reconcile-bank"])["reconcile-bank"])
    vote(@teammate, 0)
    assert_equal 1, SkillVote.tallies(["reconcile-bank"])["reconcile-bank"][:score]
  end

  test "compare alternatives: votes plus evidence pick a preferred process, which can replace the incumbent" do
    @skill.update!(stage: "firm")
    fast = Capture::Publisher.revise!(@skill, editor: @rev, attrs: { name: "reconcile-bank-auto", title: "Reconcile with auto-match" })
    assert_equal ["local", @skill.root_name], [fast.stage, fast.root_name]
    assert_equal %w[reconcile-bank reconcile-bank-auto], @skill.family.map(&:name)

    vote(@teammate, 1, fast)
    vote(@rev2, 1, fast)
    assert_raises(Capture::Voting::Error) { vote(@author, -1, @skill.reload) } # author contributed to the original
    rows = Capture::Voting.comparison(@skill.family)
    assert rows.find { |r| r[:skill].name == "reconcile-bank-auto" }[:preferred]

    sign_in @teammate
    get compare_skill_path(@skill)
    assert_response :success
    assert_includes response.body, "Preferred by colleagues"
    assert_includes response.body, "Reconcile with auto-match"
    sign_out @teammate

    use_in_sandbox
    3.times { |i| perform_workflow(@source, "user:#{@author.id}", STEPS, start: (i + 5).days.ago) }
    fast.update!(source: fast.source.merge("workflow" => STEPS)) # same steps → trips count for both in this test
    p = Capture::Promotions.new(@teammate).request!(fast, replaces: "reconcile-bank", pitch: "Faster")
    Capture::Promotions.new(@rev2).approve!(p)
    assert_equal "firm", fast.reload.stage
    assert_equal "deprecated", @skill.reload.status
    assert_raises(Capture::Promotions::Error) do
      Capture::Promotions.new(@teammate).request!(Skill.current("reconcile-bank-auto"), replaces: "nope")
    end
  end

  test "pages: skill stage panel, promotions queue, admin gates; add-in voting" do
    sign_in @teammate
    get skill_path(@skill)
    assert_includes response.body, "Gates to Firm"
    assert_includes response.body, "Is this the better way?"
    post skill_promotions_path(@skill), params: { pitch: "Ready" }
    assert_redirected_to %r{/promotions}
    get promotions_path
    assert_includes response.body, "Reconcile the bank statement"
    assert_includes response.body, "gates passed"
    put skill_vote_path(@skill), params: { value: 1, comment: "Saves me an hour" }
    assert_equal "Saves me an hour", SkillVote.find_by!(user: @teammate).comment
    sign_out @teammate

    sign_in @rev2 # reviewer: gates fail, so only "decline" is offered
    get promotions_path
    assert_includes response.body, "Can't approve until every gate passes"
    post reject_promotion_path(Promotion.sole), params: { notes: "" }
    assert_equal "open", Promotion.sole.status, "declining needs a reason"
    sign_out @rev2

    sign_in @admin
    patch admin_gates_path, params: { promotion_policy: { firm_min_score: 5, market_max_tier: "heavy" } }
    assert_equal [5, "heavy"], PromotionPolicy.current.reload.values_at(:firm_min_score, :market_max_tier)
    patch admin_gates_path, params: { promotion_policy: { market_max_tier: "nope" } }
    assert_response :unprocessable_entity

    token = AddinToken.issue!(user: @rev2).last
    put vote_api_v1_addin_skill_path("reconcile-bank"), params: { value: -1 }.to_json,
        headers: { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" }
    assert_equal({ "score" => 0, "up" => 1, "down" => 1 }, response.parsed_body["votes"])
    get api_v1_addin_skill_path("reconcile-bank"), headers: { "Authorization" => "Bearer #{token}" }
    assert_equal ["local", -1, true], response.parsed_body.values_at("stage", "my_vote", "can_vote")
  end
end
