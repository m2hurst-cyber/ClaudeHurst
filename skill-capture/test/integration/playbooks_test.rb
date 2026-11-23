require "test_helper"

# Playbooks: a curated linear workflow (the individual income tax return) installed as skills,
# with tax situations as branches, worked return by return, and new situations becoming branches.
class PlaybooksTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  KEY = "individual-income-tax".freeze

  setup do
    Capture::Taxonomy.ensure_defaults!
    @admin = make_user(role: "admin", name: "Ada Admin")
    @cpa = make_user(role: "reviewer", domains: %w[tax], name: "Casey CPA")
    @preparer = make_user(role: "member", domains: %w[tax], name: "Pat Preparer")
  end

  def install! = Capture::Playbook.find(KEY).install!(user: @admin)

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

  test "installing the tax playbook publishes a linear route of CPA skills with situation branches, idempotently" do
    pb = Capture::Playbook.find(KEY)
    assert_empty pb.problems
    r = install!
    assert_equal [21, 0, 0, 5, 11], [r.created.size, r.updated.size, r.unchanged.size, r.resources, r.situations]

    names = pb.mainline_names
    assert_equal %w[engage-the-tax-client collect-tax-documents organize-tax-financial-information report-individual-income
                    claim-deductions-and-credits prepare-the-individual-return review-the-individual-return
                    e-file-the-individual-return pay-individual-income-tax plan-next-tax-year], names
    names.each_cons(2) { |a, b| assert SkillLink.manual.exists?(from_node: a, to_node: b), "#{a} → #{b}" }
    pb.skills.each do |s|
      skill = Skill.current(s["name"])
      assert_equal ["tax", "firm", KEY], [skill.domain, skill.stage, skill.source["playbook"]]
      assert Capture::SkillStandard.check_skill(skill).clean?, "#{skill.name} meets the Agent Skills format"
    end

    se = Skill.current("report-self-employment-income")
    assert_equal "report-individual-income", se.parent_skill.name, "a situation is a branch of the step it leaves after"
    assert SkillLink.manual.exists?(from_node: se.name, to_node: "claim-deductions-and-credits"), "and rejoins the mainline at the next step"
    assert RestStop.exists?(skill_name: se.name, reason: "branch_point")
    assert_equal %w[Excel], SkillClassification.for(se.name).apps
    assert_equal ["tax/individual-income-tax/income"], SkillClassification.for(se.name).field_paths

    sit = Situation.find_by!(playbook_key: KEY, key: "self-employment")
    assert_equal ["report-individual-income", "report-self-employment-income", "active"], [sit.after_skill, sit.branch_skill, sit.status]
    assert_includes sit.forms, "Schedule SE"
    junction = Waypoint.find_by!(key: "junction:report-individual-income").body
    assert_includes junction, "Take **Report self-employment income (Schedule C)**"
    assert_includes junction, "confirm them in the current IRS forms"

    organizer = ResourceFolder.find_by!(path: "tax/individual").resources.find_by!(slug: "individual-tax-organizer")
    assert_includes SkillResource.where(resource: organizer).pluck(:skill_name), "engage-the-tax-client"
    assert Field.exists?(path: "tax/individual-income-tax/deductions-credits")

    r = install!
    assert_equal [0, 0, 21, 0], [r.created.size, r.updated.size, r.unchanged.size, r.resources], "installing again changes nothing"
    assert_raises(Capture::Playbook::Error) { Capture::Playbook.find(KEY).install!(user: @cpa) }
  end

  test "a changed playbook file updates the skill as a new version with a rest stop; a broken one isn't installed" do
    install!
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(Capture::Playbook.root.join(KEY), dir)
      ENV["SKILL_CAPTURE_PLAYBOOK_DIR"] = dir
      file = Pathname(dir).join(KEY, "skills", "pay-individual-income-tax.md")
      file.write(file.read.sub("## Checks\n", "## Checks\n\n- Same-day payments made after 8 p.m. Eastern post the next business day.\n"))
      r = install!
      assert_equal ["pay-individual-income-tax"], r.updated
      v2 = Skill.current("pay-individual-income-tax")
      assert_equal 2, v2.version
      assert_match(/Updated from the Individual income tax return playbook/, v2.source["change_note"])
      assert RestStop.where(skill_name: v2.name, skill_version: 1).exists?

      file.write(file.read.sub("name: pay-individual-income-tax", "name: claude-pays-tax"))
      e = assert_raises(Capture::Playbook::Error) { install! }
      assert_match(/frontmatter name is "claude-pays-tax"/, e.message)
    ensure
      ENV.delete("SKILL_CAPTURE_PLAYBOOK_DIR")
    end
  end

  test "a return follows the mainline, with a branch after the step for each situation that applies" do
    install!
    sign_in @preparer
    post playbook_runs_path, params: { playbook_key: KEY, reference: "123-45-6789" }
    assert_match(/looks like an SSN/, flash[:alert])
    post playbook_runs_path, params: { playbook_key: KEY, reference: "2026-0142" }
    run = PlaybookRun.last
    assert_redirected_to playbook_run_path(run)
    assert_equal 10, run.route.size

    patch playbook_run_path(run), params: { answers: { "self-employment" => "yes", "hsa" => "unsure", "rental-property" => "no", "bogus" => "yes" } }
    names = run.reload.route.map { |x| x[:name] }
    assert_equal %w[report-individual-income report-self-employment-income claim-deductions-and-credits claim-health-savings-account prepare-the-individual-return],
                 names[3..7], "branches sit right after their step; 'not sure' counts as yes"
    assert_equal [0, 12], run.progress, "a step is done only when its leg verifies"

    get playbook_run_path(run)
    assert_includes response.body, "Report self-employment income (Schedule C)"
    assert_includes response.body, "because: Did the client have self-employment"
    assert_includes response.body, "Run a conflict check" # CPA instructions rendered from the skill
    post send_route_playbook_run_path(run)
    cmd = AddinCommand.last
    assert_equal [@preparer, "load_route", 12], [cmd.target_user, cmd.kind, cmd.skill_names.size]

    other = make_user(domains: %w[tax])
    sign_in other
    get playbook_run_path(run)
    assert_response :not_found
  end

  test "describing something new: a known situation joins the route, a new one becomes a branch that goes live when published" do
    install!
    run = @preparer.playbook_runs.create!(playbook_key: KEY, reference: "R-7")
    sign_in @preparer
    post situation_playbook_run_path(run), params: { text: "They traded some bitcoin on Coinbase this year" }
    assert_match(/matched that to an existing situation/, flash[:notice])
    assert_equal "yes", run.reload.answers["investment-sales"]

    post situation_playbook_run_path(run), params: { text: "Client sold their main home, SSN 123-45-6789, for 850,000" }
    sit = Situation.find_by!(playbook_key: KEY, status: "proposed")
    c = sit.candidate
    assert_equal ["branch", "report-individual-income", "report-individual-income"], [c.proposal_kind, c.base_skill.name, sit.after_skill]
    assert_equal "yes", run.reload.answers[sit.key]
    refute_includes c.review_notes, "123-45-6789"
    refute_includes c.review_notes, "850,000"
    assert c.drafted?
    assert Capture::SkillStandard.check_candidate(c).ok?
    assert @cpa.notifications.where(kind: "skill_candidate").exists?
    pending = run.route.find { |x| x[:situation] == sit }
    assert pending[:pending], "the branch shows as in review until it's published"

    branch = Capture::Publisher.publish!(c, reviewer: @cpa)
    sit.reload
    assert_equal ["active", branch.name], [sit.status, sit.branch_skill]
    assert_equal "report-individual-income", branch.parent_skill.name
    assert SkillLink.manual.exists?(from_node: branch.name, to_node: "claim-deductions-and-credits")
    assert_includes Waypoint.find_by!(key: "junction:report-individual-income").body, branch.title
    assert_not run.reload.route.find { |x| x[:situation] == sit }[:pending]

    other = @preparer.playbook_runs.create!(playbook_key: KEY, reference: "R-8")
    assert_includes Situation.for_playbook(KEY).pluck(:key), sit.key, "every later return gets asked about it too"
    assert_nil other.answers[sit.key]
  end

  test "the CPA advisor (AI) sees a redacted description and the playbook's structure only" do
    install!
    run = @preparer.playbook_runs.create!(playbook_key: KEY, reference: "R-9")
    ai = FakeClaude.new(match_key: "none", after_step: "claim-deductions-and-credits", question: "Did the client buy a qualifying electric vehicle?",
                        title: "Claim the clean vehicle credit", description: "Claims the clean vehicle credit on Form 8936. Use when the client bought a qualifying electric vehicle.",
                        forms: ["Form 8936"], steps: ["Get the dealer's time-of-sale report", "Check income and price limits"], keywords: ["electric vehicle", "ev"],
                        rationale: "Not covered by an existing situation.")
    outcome, sit, r = Capture::Situations.describe!(run, "Bought a Tesla for $48,990 on 3/14, VIN 5YJ3E1EA7KF317000, email me@x.com", user: @preparer, client: ai)
    assert_equal [:proposed, "ai", "claim-deductions-and-credits", ["Form 8936"]], [outcome, r.by, sit.after_skill, sit.forms]
    sent = ai.req[:messages].first[:content]
    refute_match(/48,990|3\/14|me@x\.com|317000/, sent)
    assert_includes JSON.parse(sent)["situations"].map { |s| s["key"] }, "self-employment"
    assert_equal "Claim the clean vehicle credit", sit.candidate.draft_title
    assert_equal "claim-deductions-and-credits", ai.req.dig(:output_config, :format, :schema, :properties, :after_step, :enum).fifth
  end

  test "pages: playbooks, the route, and a return" do
    sign_in @admin
    get playbooks_path
    assert_includes response.body, "Individual income tax return"
    assert_includes response.body, "Not installed"
    get playbook_path(KEY)
    assert_includes response.body, "Install"
    post install_playbook_path(KEY)
    assert_match(/21 created/, flash[:notice])
    get playbook_path(KEY)
    assert_includes response.body, "Start a return"
    assert_includes response.body, "⑂ If"
    assert_includes response.body, "Engagement letter (individual return)"
    sign_in @preparer
    post install_playbook_path(KEY)
    assert_match(/Only admins/, flash[:alert])
  end
end
