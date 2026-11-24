require "test_helper"

# "Copy for LLM" / "View as Markdown": every page an agent might want has a .md version.
class LlmMarkdownTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    PromotionPolicy.current.update!(initial_stage: "firm")
    Capture::Taxonomy.ensure_defaults!
    @admin = make_user(role: "admin", name: "Ada Admin")
    @rae = make_user(role: "member", domains: %w[finance bql], name: "Rae")
    @other = make_user(role: "member", domains: %w[legal], name: "Otto")
    steps = %w[x.a:1 x.b:2]
    c = SkillCandidate.create!(signature: SkillCandidate.signature_for(steps), steps: steps, domain: "finance", status: "drafted",
                               draft_name: "close-the-month", draft_title: "Close the month", draft_description: "Closes the month. Use at month end.", draft_body: "1. a\n2. b")
    @skill = Capture::Publisher.publish!(c, reviewer: @admin)
    SkillRun.create!(skill_name: @skill.name, agent: "a", model: "m", input_tokens: 100, output_tokens: 50, duration_ms: 2000)
  end

  test "a skill as LLM-ready Markdown: SKILL.md, usage, where to report runs; inline or downloaded" do
    sign_in @rae
    get skill_path(@skill)
    assert_select "[data-controller=llm-copy][data-llm-copy-url-value=?]", skill_path(@skill, format: :md)
    assert_select "button", text: /Copy for LLM/
    assert_select "dialog h2", text: "close-the-month.md"
    get skill_path(@skill, format: :md)
    assert_equal "text/markdown; charset=utf-8", response.media_type + "; charset=" + response.charset
    assert response.body.start_with?("---\nname: close-the-month\n")
    assert_includes response.body, "## AI usage (last 90 days)"
    assert_includes response.body, "POST /api/v1/skills/close-the-month/runs"
    assert_match(/inline/, response.headers["Content-Disposition"])
    get skill_path(@skill, format: :md, download: 1)
    assert_match(/attachment; filename="close-the-month.md"/, response.headers["Content-Disposition"])
  end

  test "flows, runs, formula libraries, agent guides and transfers have .md versions" do
    Capture::Playbook.find("bql-analysis").install!(user: @admin)
    flow = Flow.create!(user: @rae, name: "Month end", steps: Flow.normalize_steps([{ title: "Collect | data", app: "Excel" }, { kind: "pause", pause_mode: "timer", pause_minutes: 60 }, { title: "Report", app: "Word", skill_name: "close-the-month" }]))
    run = FlowRun.start!(flow, user: @rae)
    sign_in @rae
    get flow_path(flow, format: :md)
    assert_includes response.body, "| 1 | Collect \\| data | Excel | Rae |"
    assert_includes response.body, "| ⏸ | Pause | — | — | — | Wait 1 hour |"
    assert_includes response.body, "`close-the-month`"
    get flow_run_path(run, format: :md)
    assert_includes response.body, "**Now:** task 1, Collect | data (Rae, Excel)"
    assert_includes response.body, "**ready (now)**"
    get formulas_path(provider: "bql", format: :md)
    assert_includes response.body, "| `revenue` | Revenue | `=BQL({security},\"sales_rev_turn(fpt={fpt}, fpo={fpo})\")` | fpt=A, fpo=0 | unverified |"
    get guide_formulas_path(provider: "bql", format: :md)
    assert response.body.start_with?("# Agent guide")
    t = SkillTransfer.offer!(sender: @admin, recipient: @rae, names: ["close-the-month"])
    get transfer_path(t, format: :md)
    assert_includes response.body, "## Contract log"
    get flow_path(flow)
    assert_select "[data-llm-copy-url-value=?]", flow_path(flow, format: :md)

    sign_in @other
    get flow_path(flow, format: :md)
    assert_response :redirect
  end

  test "the add-in gets the same Markdown for the skill view and memory" do
    h = { "Authorization" => "Bearer #{AddinToken.issue!(user: @rae, host: 'Excel').last}" }
    get "/api/v1/addin/skills/close-the-month", headers: h
    assert response.parsed_body["markdown"].start_with?("---\nname: close-the-month")
    get "/api/v1/addin/bundles/close-the-month", headers: h
    assert_includes response.parsed_body["markdown"].to_s, "## AI usage"
  end
end
