require "test_helper"

# The AI writes the macro the first time it does a scriptable task; once a person approves it, later
# runs skip the AI. Macros can then be shared: taken onto another task, exported, imported.
class MacroAuthoringTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  class FakeClaude
    attr_reader :reqs
    Msg = Struct.new(:stop_reason, :content)
    Block = Struct.new(:type, :text)
    def initialize(answer) = (@answer = answer) && (@reqs = [])
    def beta = self
    def messages = self
    def create(**req)
      @reqs << req
      Msg.new(:end_turn, [Block.new(:text, @answer.to_json)])
    end
  end

  GOOD = { language: "addin_js", confidence: "high", steps: ["read the used range", "copy each chart"],
           leaves_to_ai: [], caveats: ["assumes one chart per sheet"],
           code: "async function run(context) {\n  const s = context.workbook.worksheets.getActiveWorksheet();\n  s.charts.load('items/name');\n  await context.sync();\n  return `Copied ${s.charts.items.length} charts`;\n}" }.freeze

  setup do
    PromotionPolicy.current.update!(initial_stage: "firm")
    Capture::Models.ensure_defaults!
    @admin = make_user(role: "admin", name: "Ada Admin")
    @rev = make_user(role: "reviewer", domains: %w[finance], name: "Rev")
    @rae = make_user(role: "member", domains: %w[finance], name: "Rae")
    @agent, @token = Source.issue!(name: "Research agent", kind: "integration")
    @skill = publish("tidy-the-pack", "Tidy the pack", "Apply the template to every sheet and refresh the links.")
  end

  def publish(name, title, desc)
    steps = ["x.#{name}:a", "x.#{name}:b"]
    c = SkillCandidate.create!(signature: SkillCandidate.signature_for(steps), steps: steps, domain: "finance", status: "drafted",
                               draft_name: name, draft_title: title, draft_description: desc, draft_body: "1. a\n2. b")
    Capture::Publisher.publish!(c, reviewer: @admin)
  end

  def h = { "Authorization" => "Bearer #{@token}", "Content-Type" => "application/json" }

  test "the AI writes the macro from the run it just did, and says what it can't script" do
    ai = FakeClaude.new(GOOD.merge(leaves_to_ai: ["deciding which sheets are in scope"], confidence: "medium"))
    s = Capture::MacroWriter.call(title: @skill.title, instructions: @skill.description, app: "Excel", skill: @skill,
                                  note: "Applied the template to 6 sheets and refreshed.", usage: { "input_tokens" => 9_000, "output_tokens" => 1_200 }, client: ai)
    assert_equal ["addin_js", "medium", ["deciding which sheets are in scope"]], s.values_at("language", "confidence", "leaves_to_ai")
    assert_match(/async function run/, s["code"])
    sent = ai.reqs.first
    assert_match(/deterministic Office macros/, sent[:system_])
    assert_match(/Applied the template to 6 sheets/, sent[:messages].first[:content])

    # nothing worth proposing is nothing proposed
    assert_nil Capture::MacroWriter.call(title: "Write the memo", client: FakeClaude.new(language: "none", confidence: "none", code: "", steps: [], leaves_to_ai: [], caveats: []))
    assert_nil Capture::MacroWriter.call(title: "Half a script", client: FakeClaude.new(GOOD.merge(code: "const x = 1 // no run()")))
  end

  test "an agent hands over the script with the run it just finished; a reviewer approves it; later runs skip the AI" do
    post "/api/v1/skills/#{@skill.name}/runs",
         params: { model: "claude-sonnet-5-5", input_tokens: 9_000, output_tokens: 1_200, duration_ms: 30_000,
                   macro: { language: "addin_js", code: GOOD[:code], steps: ["refresh", "format"], confidence: "high" } }.to_json, headers: h
    assert_response :created
    r = MacroReview.find(response.parsed_body.dig("macro_review", "id"))
    assert_equal %w[ai proposed], [r.written_by, r.status]
    assert_match(/wrote this script from the run it just finished/, r.reason)
    assert Notification.exists?(user: @rev, kind: "macro_review")
    refute r.runnable_in_addin?, "not until a person approves it"

    sign_in @rev
    patch macro_review_path(r), params: { macro_review: { status: "approved", code: r.code, language: "addin_js" } }
    assert r.reload.approved?
    sign_out @rev

    # from now on the task is a macro: no tokens anticipated, and the add-in is handed the script
    e = Capture::Estimator.for_step({ "title" => @skill.title, "skill_name" => @skill.name, "engine" => "macro" })
    assert_equal [0, 0.0], [e["tokens"], e["cost"]]
    ah = { "Authorization" => "Bearer #{AddinToken.issue!(user: @rae, host: 'Excel').last}", "Content-Type" => "application/json" }
    get "/api/v1/addin/skills/#{@skill.name}", headers: ah
    assert_equal [true, "addin_js"], response.parsed_body.dig("macro").values_at("runnable", "language")
    get "/api/v1/bundles/#{@skill.name}", headers: h
    assert_match(/async function run/, response.parsed_body.dig("macro", "code"))

    post "/api/v1/addin/skills/#{@skill.name}/runs", params: { engine: "macro", model: "macro", input_tokens: 0, output_tokens: 0, duration_ms: 900 }.to_json, headers: ah
    assert_response :created
    run = SkillRun.order(:id).last
    assert_equal ["macro", 0, 0.0], [run.engine, run.total_tokens, run.cost.to_f]
    assert_operator r.reload.tokens_saved, :>, 0, "the review counts what the macro saved"
  end

  test "a flow task asks the AI for the macro after its first AI run, and never for an approved or rejected one" do
    flow = Flow.create!(user: @rae, name: "Pack", steps: Flow.normalize_steps([
      { id: "t1", title: "Apply the template to every sheet", app: "Excel", skill_name: @skill.name },
      { id: "t2", title: "Recommend what to cut", app: "Word" }
    ]))
    run = FlowRun.start!(flow, user: @rae)
    assert_enqueued_with(job: MacroDraftJob) do
      run.complete!(index: 0, user: @rae, note: "Template applied to 6 sheets", usage: { "model" => "claude-sonnet-5-5", "input_tokens" => 8_000, "output_tokens" => 900, "duration_ms" => 20_000 })
    end

    Capture::MacroScreen.review!(kind: "flow_step", key: "#{flow.id}:t2", title: "Recommend what to cut").update!(status: "rejected", reviewed_by: @rev)
    assert_no_enqueued_jobs(only: MacroDraftJob) do
      run.complete!(index: 1, user: @rae, note: "Memo written", usage: { "model" => "claude-opus-5-5", "input_tokens" => 20_000, "output_tokens" => 4_000 })
    end

    # the job writes the script and files it for review
    Capture::MacroWriter.stub(:call, GOOD.stringify_keys) do
      MacroDraftJob.perform_now("flow_step", "#{flow.id}:t1", "Apply the template to every sheet", app: "Excel",
                                instructions: nil, skill_name: @skill.name, note: "Template applied to 6 sheets", run_id: run.id)
    end
    r = MacroReview.for_subject("flow_step", "#{flow.id}:t1")
    assert_equal ["ai", "proposed", "high"], [r.written_by, r.status, r.confidence]
    assert_match(/approve it and later runs skip the AI/, r.reason)
  end

  test "sharing: take an approved macro onto another task, export it, import it back" do
    r = Capture::MacroScreen.review!(kind: "skill", key: @skill.name, title: @skill.title, instructions: @skill.description, user: @rae)
    r.update!(status: "approved", reviewed_by: @rev, written_by: "ai", suggestion: r.suggestion.merge("code" => GOOD[:code], "leaves_to_ai" => ["which sheets"]))
    other = publish("tidy-the-board-pack", "Tidy the board pack", "Apply the template and refresh.")

    copy = r.copy_to!(kind: "skill", key: other.name, title: other.title, user: @rae)
    assert_equal ["proposed", r.id, GOOD[:code]], [copy.status, copy.copied_from_id, copy.code]
    assert_match(/Check it fits this task/, copy.reason)
    assert_raises(ArgumentError, "only an approved macro travels") { copy.copy_to!(kind: "skill", key: "x", title: "x", user: @rae) }
    copy.update!(status: "approved", reviewed_by: @rev)
    assert_raises(ArgumentError) { r.copy_to!(kind: "skill", key: other.name, title: other.title, user: @rae) }

    pkg = r.as_package
    assert_equal ["skill-capture.macro/1", "addin_js", @skill.name], pkg.values_at("format", "language", "from")
    fresh = MacroReview.from_package(pkg, user: @rae, kind: "skill", key: "somewhere-else")
    assert_equal ["proposed", "private", GOOD[:code]], [fresh.status, fresh.visibility, fresh.code]
    assert_match(/Imported from/, fresh.reason)
    assert_raises(ArgumentError) { MacroReview.from_package({ "format" => "something/1", "code" => GOOD[:code] }, user: @rae) }
    assert_raises(ArgumentError) { MacroReview.from_package(pkg.merge("code" => ""), user: @rae) }

    sign_in @rev
    patch share_macro_review_path(r, visibility: "firm")
    assert_equal "firm", r.reload.visibility
    get library_macro_reviews_path
    assert_select "a", text: @skill.title
    assert_select "option", text: /Tidy the board pack/
    get export_macro_review_path(r)
    assert_equal "skill-capture.macro/1", JSON.parse(response.body)["format"]
    post import_macro_reviews_path, params: { package: response.body }
    assert_redirected_to macro_review_path(MacroReview.order(:id).last)
    post import_macro_reviews_path, params: { package: "not json" }
    assert_match(/Couldn't import/, flash[:alert])
    sign_out @rev

    sign_in @rae
    patch share_macro_review_path(r, visibility: "market")
    assert_equal "firm", r.reload.visibility, "only reviewers change who sees a macro"
  end
end
