require "test_helper"

# Choosing the engine and the model before a task runs: macro suitability (screened, then reviewed by a
# person), task nature and complexity, anticipated tokens / time / cost, a split task run by two
# workers at once, and the running tally inside a run.
class MacrosModelsEstimatesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    PromotionPolicy.current.update!(initial_stage: "firm")
    Capture::Models.ensure_defaults!
    @admin = make_user(role: "admin", name: "Ada Admin")
    @rae = make_user(role: "member", domains: %w[finance], name: "Rae")
    @rev = make_user(role: "reviewer", domains: %w[finance], name: "Rev")
    @agent, @agent_token = Source.issue!(name: "Research agent", kind: "integration")
    @agent2, @agent2_token = Source.issue!(name: "Writer agent", kind: "integration")
    @skill = publish("collect-charts", "Collect workbook charts into an appendix", "Copy every chart from the workbook into appendix slides, one per slide, with its title and source.")
  end

  def publish(name, title, desc)
    steps = ["x.#{name}:a", "x.#{name}:b"]
    c = SkillCandidate.create!(signature: SkillCandidate.signature_for(steps), steps: steps, domain: "finance", status: "drafted",
                               draft_name: name, draft_title: title, draft_description: desc, draft_body: "1. a\n2. b")
    Capture::Publisher.publish!(c, reviewer: @admin)
  end

  def agent_h(token) = { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" }

  test "nature and complexity place a task in a tier, and the tier picks the model" do
    assert_equal "programmatic", Capture::TaskProfile.infer("Copy every chart into appendix slides, one per slide")
    assert_equal "critical", Capture::TaskProfile.infer("Write the white paper and recommend a course of action")
    assert_equal "analytic", Capture::TaskProfile.infer("Regress Y on the chosen variables and compare R²")
    assert_equal "opaque", Capture::TaskProfile.infer("Investigate why the margin moved; root cause unclear")
    # the most demanding nature in the text wins
    assert_equal "critical", Capture::TaskProfile.infer("Summarize the data, then recommend what to do")

    assert_equal "small", Capture::TaskProfile.tier_for(nature: "linear", complexity: "medium")
    assert_equal "standard", Capture::TaskProfile.tier_for(nature: "linear", complexity: "high")
    assert_equal "deep", Capture::TaskProfile.tier_for(nature: "critical", complexity: "medium")
    assert_equal "small", Capture::TaskProfile.tier_for(nature: "programmatic", complexity: "low"), "no approved macro: the cheapest model, not a macro"
    assert_equal "macro", Capture::TaskProfile.tier_for(nature: "programmatic", complexity: "low", macro_ready: true)

    p = Capture::TaskProfile.for_step({ "title" => "Write the board memo", "instructions" => "Recommend a course of action." })
    assert_equal %w[critical deep claude-opus-5-5], p.values_at("nature", "tier", "model")
    assert_equal "claude-haiku-5-5", Capture::TaskProfile.for_step({ "title" => "Collect the files", "complexity" => "low" })["model"]
    assert_equal "claude-sonnet-5-5", Capture::TaskProfile.for_step({ "title" => "Collect the files", "model" => "claude-sonnet-5-5" })["model"], "a named model wins"
  end

  test "the macro layer screens a task, a person approves it, and then it runs with no tokens" do
    s = Capture::MacroScreen.screen(title: @skill.title, instructions: @skill.description)
    assert_equal "macro", s["verdict"]
    assert_includes s["signals"]["for"], "repeats over every item"
    assert_equal "ai", Capture::MacroScreen.screen(title: "Write the white paper", instructions: "Draft the findings and implications.")["verdict"]
    assert_equal "partial", Capture::MacroScreen.screen(title: "Format the pack", instructions: "Apply the template to every sheet, then summarize what changed.")["verdict"]

    r = Capture::MacroScreen.review!(kind: "skill", key: @skill.name, title: @skill.title, instructions: @skill.description, user: @rae)
    assert_equal %w[proposed macro addin_js], [r.status, r.verdict, r.language]
    assert_match(/async function run\(context\)/, r.code)
    refute r.runnable_in_addin?, "not until it's approved"
    r.update!(status: "approved", reviewed_by: @rev)
    assert r.reload.runnable_in_addin?

    # approving can't happen with an empty macro
    empty = MacroReview.new(subject_kind: "skill", subject_key: "x", title: "x", verdict: "macro", status: "approved")
    refute empty.valid?
    assert_match(/needs code/, empty.errors.full_messages.to_sentence)

    # and a screen never overwrites an approved review
    r.update!(suggestion: r.suggestion.merge("code" => "async function run(c) { return 'mine'; }"))
    Capture::MacroScreen.review!(kind: "skill", key: @skill.name, title: @skill.title, user: @rae)
    assert_equal "async function run(c) { return 'mine'; }", r.reload.code
  end

  test "estimates: priors by nature, measurement once runs exist, zero for a macro" do
    e = Capture::Estimator.for_step({ "title" => "Write the white paper", "instructions" => "Recommend what to do." })
    assert_equal ["critical", "claude-opus-5-5", 25_000], [e["nature"], e["model"], e["tokens"]]
    assert_in_delta 0.675, e["cost"], 0.001
    assert_match(/estimated from critical/, e["basis"])

    3.times { SkillRun.create!(skill_name: @skill.name, agent: "a", model: "claude-haiku-5-5", input_tokens: 1_000, output_tokens: 200, duration_ms: 4_000) }
    m = Capture::Estimator.for_step({ "title" => @skill.title, "skill_name" => @skill.name, "model" => "claude-haiku-5-5" })
    assert_equal [1_200, "measured (3 runs)"], [m["tokens"], m["basis"]]
    assert_in_delta 4.0, m["seconds"], 0.1

    macro = Capture::Estimator.for_step({ "title" => @skill.title, "engine" => "macro" })
    assert_equal [0, 0.0, "macro"], [macro["tokens"], macro["cost"], macro["engine"]]
    assert_equal "reviewed macro: no tokens", macro["basis"]
  end

  test "a split task: a macro and an agent work side by side, and the task hands off when both are done" do
    flow = Flow.create!(user: @rae, name: "Appendix", steps: Flow.normalize_steps([
      { id: "s1", title: "Appendix", app: "PowerPoint", skill_name: @skill.name, parts: [
        { id: "pa", title: "Copy the charts", engine: "macro", assignee: "me" },
        { id: "pb", title: "Caption each one", engine: "ai", assignee: "agent:#{@agent.id}", model: "claude-haiku-5-5" }
      ] },
      { id: "s2", title: "Review the pack", app: "PowerPoint", assignee: "me" }
    ]))
    Capture::MacroScreen.review!(kind: "flow_step", key: "#{flow.id}:s1", title: "Appendix", instructions: "Copy every chart, one per slide.", user: @rae).update!(status: "approved", reviewed_by: @rev)

    est = flow.estimate
    assert_equal true, est["steps"][0]["split"]
    assert_equal %w[macro claude-haiku-5-5], est["steps"][0]["parts"].map { |p| p["model"] }
    assert_equal est["steps"][0]["parts"].map { |p| p["seconds"] }.max, est["steps"][0]["seconds"], "parts run side by side"

    run = FlowRun.start!(flow, user: @rae)
    assert_equal %w[ready ready], Flow.parts(run.current).map { |p| p["state"] }
    assert_equal 2, AddinCommand.pending.where(kind: "flow_task").count, "a part each"
    assert_equal "macro", AddinCommand.pending.find_by("payload->>'part_id' = 'pa'").payload.dig("macro", "language").then { "macro" }
    assert AddinCommand.pending.find_by("payload->>'part_id' = 'pa'").payload.dig("macro", "runnable")

    e = assert_raises(FlowRun::Error) { run.complete!(index: 0, user: @rae) }
    assert_match(/split into parts/, e.message)
    assert_raises(FlowRun::Error) { run.complete_part!(index: 0, part_id: "pb", user: @rev) } # not theirs
    assert_raises(FlowRun::Error) { run.complete_part!(index: 0, part_id: "nope", user: @rae) }

    run.complete_part!(index: 0, part_id: "pa", user: @rae, note: "12 charts copied", usage: { "duration_ms" => 1_800 })
    assert_equal 0, run.reload.current_index, "the task waits for the other part"
    assert_equal "⚙ Macro", Flow.parts(run.current)[0]["by"]
    macro_run = SkillRun.order(:id).last
    assert_equal ["macro", "macro", 0, "pa"], [macro_run.engine, macro_run.model, macro_run.total_tokens, macro_run.part_id]
    assert_operator MacroReview.find_by(subject_key: "#{flow.id}:s1").tokens_saved, :>, 0

    post "/api/v1/flow_runs/#{run.id}/complete_part?step=0&part=pb",
         params: { note: "Captions written", usage: { model: "claude-haiku-5-5", input_tokens: 900, output_tokens: 300, duration_ms: 7_000 } }.to_json, headers: agent_h(@agent_token)
    assert_response :success
    assert_equal [1, "done"], [run.reload.current_index, run.steps[0]["state"]]
    assert_equal "⚙ Macro + 🤖 Research agent", run.steps[0]["by"]
    ai_run = SkillRun.where(engine: "ai").order(:id).last
    assert_equal ["claude-haiku-5-5", 1_200, "pb"], [ai_run.model, ai_run.total_tokens, ai_run.part_id]
    assert_in_delta 0.0024, ai_run.cost.to_f, 0.0001
  end

  test "the run carries an anticipated cost and a running tally" do
    flow = Flow.create!(user: @rae, name: "Report", steps: Flow.normalize_steps([
      { id: "a", title: "Collect the source files", app: "Excel", complexity: "low" },
      { id: "b", title: "Write the white paper and recommend next steps", app: "Word", assignee: "agent:#{@agent2.id}" }
    ]))
    est = flow.estimate
    assert_equal %w[lookup critical], est["steps"].map { |s| s["nature"] }
    assert_equal %w[claude-haiku-5-5 claude-opus-5-5], est["steps"].map { |s| s["model"] }
    assert_equal est["steps"].sum { |s| s["tokens"] }, est["tokens"]

    run = FlowRun.start!(flow, user: @rae)
    assert_equal est["tokens"], run.estimate["tokens"]
    assert_equal %w[lookup critical], run.steps.map { |s| s["nature"] }, "the profile is pinned when the run starts"

    run.complete!(index: 0, user: @rae, note: "In the Data sheet", usage: { "model" => "claude-haiku-5-5", "input_tokens" => 2_000, "output_tokens" => 400, "duration_ms" => 9_000 })
    t = run.reload.tally
    assert_equal [2_400, 1], [t.dig("spent", "tokens"), t.dig("spent", "steps")]
    assert_in_delta 0.004, t.dig("spent", "cost"), 0.0005
    assert_equal est["steps"][1]["tokens"], t.dig("remaining", "tokens")
    assert_equal 2_400 + est["steps"][1]["tokens"], t.dig("projected", "tokens")

    sign_in @rae
    get flow_run_path(run)
    assert_select "section[aria-label='Cost and time']"
    assert_select "div", text: /Projected total/
    get flow_path(flow)
    assert_select "[data-flow-map-estimate-value]"
  end

  test "the same task priced on every model, and trials of what actually happened" do
    plan = Capture::Estimator.trial_plan({ "title" => "Chart the data", "skill_name" => @skill.name })
    assert_equal %w[claude-haiku-5-5 claude-sonnet-5-5 claude-opus-5-5], plan.map { |m| m["model"] }
    assert_operator plan.first["cost"], :<, plan.last["cost"]

    [["claude-haiku-5-5", 1_000, 300, "failed"], ["claude-haiku-5-5", 1_100, 320, "succeeded"], ["claude-opus-5-5", 1_000, 400, "succeeded"]].each do |m, i, o, st|
      post "/api/v1/skills/#{@skill.name}/runs", params: { model: m, input_tokens: i, output_tokens: o, duration_ms: 5_000, status: st, trial_of: "appendix-trial" }.to_json, headers: agent_h(@agent_token)
      assert_response :created
    end
    res = Capture::Estimator.trial_results("appendix-trial")
    assert_equal %w[claude-haiku-5-5 claude-opus-5-5], res.map { |r| r["model"] }, "cheapest first"
    assert_equal [2, 1], res.map { |r| r["runs"] }
    assert_equal [1, 1], res.map { |r| r["succeeded"] }
    sign_in @rae
    get skill_path(@skill)
    assert_select "#agent-usage h3", text: /What a run costs on each model/
    assert_select "#agent-usage code", text: "appendix-trial"
  end

  test "the macro queue: screen everything, approve, reject; only reviewers decide" do
    sign_in @rae
    get macro_reviews_path
    assert_select "h1", text: "Macro review"
    post screen_all_macro_reviews_path
    assert_response :redirect
    sign_out @rae

    sign_in @rev
    post screen_all_macro_reviews_path
    r = MacroReview.find_by!(subject_kind: "skill", subject_key: @skill.name)
    assert_equal "macro", r.verdict
    get macro_review_path(r)
    assert_select "button[value=approved]", text: /Approve: run as a macro/
    patch macro_review_path(r), params: { macro_review: { status: "approved", code: "async function run(context) { return 'done'; }", language: "addin_js", review_notes: "Checked against last month's pack" } }
    assert_equal ["approved", @rev.id], [r.reload.status, r.reviewed_by_id]
    assert r.runnable_in_addin?
    get macro_review_path(r, format: :md)
    assert_includes response.body, "async function run(context)"
    patch macro_review_path(r), params: { macro_review: { status: "rejected", code: r.code } }
    assert_equal "rejected", r.reload.status
  end

  test "the add-in gets the macro for the current task and reports a macro run" do
    flow = Flow.create!(user: @rae, name: "Pack", steps: Flow.normalize_steps([{ id: "m1", title: "Copy every chart into the appendix", app: "Excel", engine: "macro", skill_name: @skill.name }]))
    Capture::MacroScreen.review!(kind: "flow_step", key: "#{flow.id}:m1", title: "Copy every chart", user: @rae)
                        .update!(status: "approved", reviewed_by: @rev, suggestion: { "language" => "addin_js", "code" => "async function run(context) { return 'copied 12 charts'; }" })
    run = FlowRun.start!(flow, user: @rae)
    h = { "Authorization" => "Bearer #{AddinToken.issue!(user: @rae, host: 'Excel').last}", "Content-Type" => "application/json" }
    get "/api/v1/addin/flow_runs/#{run.id}", headers: h
    body = response.parsed_body
    assert_equal "copied 12 charts", body.dig("macros", "step", "code")[/'(.+)'/, 1]
    assert_equal 0, body.dig("budget", "estimated_tokens"), "a macro-only run anticipates no tokens"
    post "/api/v1/addin/flow_runs/#{run.id}/complete?step=0",
         params: { note: "copied 12 charts", usage: { model: "macro", input_tokens: 0, output_tokens: 0, duration_ms: 1_400 } }.to_json, headers: h
    assert_response :success
    assert_equal "completed", run.reload.status
    assert_equal ["macro", 0], SkillRun.order(:id).last.then { |r| [r.engine, r.total_tokens] }
    assert_operator MacroReview.find_by(subject_key: "#{flow.id}:m1").tokens_saved, :>, 0
  end

  test "the model catalogue prices runs and admins edit it" do
    assert_equal %w[macro small standard deep], ModelProfile.order(:position).pluck(:tier)
    assert_equal 0.0, Capture::Models.cost("macro", 10_000, 1_000)
    assert_in_delta 0.03, Capture::Models.cost("claude-sonnet-5-5", 5_000, 1_000).to_f, 0.001
    sign_in @rae
    get model_profiles_path
    assert_select "h1", text: "Models and what they cost"
    patch model_profile_path(ModelProfile.find_by(key: "claude-haiku-5-5")), params: { model_profile: { input_cost: 2 } }
    assert_response :redirect
    assert_equal 1.0, ModelProfile.find_by(key: "claude-haiku-5-5").input_cost.to_f, "members don't set prices"
    sign_in @admin
    patch model_profile_path(ModelProfile.find_by(key: "claude-haiku-5-5")), params: { model_profile: { input_cost: 2 } }
    assert_equal 2.0, ModelProfile.find_by(key: "claude-haiku-5-5").input_cost.to_f
  end
end
