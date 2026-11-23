require "test_helper"

# Save / extend / branch protocols (triggers that prompt people about their own repeated work)
# and rest stops (automatic, restorable snapshots so any version or branch can be reverted).
class ProtocolsRestStopsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  A, B, C = %w[excel.step:import-statement excel.step:match-payments excel.step:investigate-unmatched]
  X, Y, Z = %w[excel.step:flag-old-items excel.step:email-controller excel.step:auto-match-rules]

  setup do
    Capture::Taxonomy.ensure_defaults!
    @admin = make_user(role: "admin", name: "Ada")
    @rev = make_user(role: "reviewer", domains: %w[finance], name: "Rae Reviewer")
    @me = make_user(role: "member", domains: %w[finance], name: "Mo Member")
    @src = Source.for_office_host("Excel")
    @skill = publish("reconcile-bank", "Reconcile the bank statement", [A, B, C])
  end

  def publish(name, title, steps, body: "1. Import\n2. Match\n3. Investigate")
    c = SkillCandidate.create!(signature: SkillCandidate.signature_for(steps), steps: steps, domain: "finance", status: "drafted",
                               draft_name: name, draft_title: title, draft_description: "When the bank statement arrives.", draft_body: body)
    Capture::Publisher.publish!(c, reviewer: @admin)
  end

  def work(user, steps, times:, start: 2.days.ago)
    times.times { |i| perform_workflow(@src, user.actor_key, steps, start: start + i.hours, session: "s-#{SecureRandom.hex(3)}") }
  end

  # ---------- triggers ----------

  test "extend: finishing a skill and then doing the same extra steps prompts to extend it" do
    work(@me, [A, B, C, X, Y], times: 2)
    prompts = Capture::Prompter.call(@me)
    assert_equal 1, prompts.size
    p = prompts.first
    assert_equal ["extend", "reconcile-bank", [A, B, C, X, Y]], [p.kind, p.skill_name, p.steps]
    assert_equal [X, Y], p.evidence["added"]
    assert_equal %w[extend branch], p.choices
    assert_match(/add 2 steps every time \(2×\)/, p.headline)
    assert_equal 1, @me.notifications.where(kind: "prompt").count

    work(@me, [A, B, C, X, Y], times: 1)
    assert_empty Capture::Prompter.call(@me), "the same pattern doesn't raise a second prompt"
    assert_equal 3, p.reload.occurrences

    sign_in @me
    post respond_prompt_path(p), params: { choice: "extend" }
    c = SkillCandidate.order(:id).last
    assert_redirected_to skill_candidate_path(c)
    assert_equal ["extend", @skill, "reconcile-bank", [A, B, C, X, Y]], [c.proposal_kind, c.base_skill, c.draft_name, c.steps]
    assert_equal ["accepted", "extend", c], [p.reload.status, p.response, p.candidate]
    assert @rev.notifications.where(kind: "skill_candidate").exists?
    get skill_candidate_path(c)
    assert_includes response.body, "Extends"

    v2 = Capture::Publisher.publish!(c, reviewer: @rev)
    assert_equal ["reconcile-bank", 2, @skill], [v2.name, v2.version, v2.parent_skill]
    assert_equal "superseded", @skill.reload.status
    reasons = RestStop.where(skill_name: "reconcile-bank").order(:id).pluck(:reason, :skill_version)
    assert_includes reasons, ["published", 1], "v1 is kept (the before-update snapshot is skipped when it's identical)"
    assert_includes reasons, ["revised", 2]
  end

  test "branch: doing a skill your own way prompts a branch that starts in the sandbox and can revert to its parent" do
    PromotionPolicy.current.update!(initial_stage: "local")
    work(@me, [A, Z, C], times: 2)
    p = Capture::Prompter.call(@me).sole
    assert_equal ["branch", [A, Z, C], [Z], [B]], [p.kind, p.steps, p.evidence["added"], p.evidence["removed"]]

    sign_in @me
    post respond_prompt_path(p), params: { choice: "branch", title: "Reconcile with auto-match rules" }
    c = SkillCandidate.order(:id).last
    assert_equal ["branch", "reconcile-with-auto-match-rules", "Reconcile with auto-match rules"], [c.proposal_kind, c.draft_name, c.draft_title]
    branch = Capture::Publisher.publish!(c, reviewer: @rev)
    assert_equal [@skill, "local", 1], [branch.parent_skill, branch.stage, branch.version]
    assert_equal "published", @skill.reload.status, "the original is untouched"

    start = RestStop.find_by!(skill_name: branch.name, reason: "branch_point")
    assert start.pinned
    assert_equal [A, B, C], start.workflow, "a branch's first rest stop is its parent as it was"
    assert_equal "reconcile-bank@1", start.snapshot["branched_from"]
    assert RestStop.exists?(skill_name: branch.name, reason: "branched")

    sign_in @rev
    post revert_rest_stop_path(start)
    reverted = Skill.current(branch.name)
    assert_redirected_to skill_path(reverted, anchor: "rest-stops")
    assert_equal [2, [A, B, C], "1. Import\n2. Match\n3. Investigate"], [reverted.version, reverted.source["workflow"], reverted.body]
    assert_equal "local", reverted.stage, "reverting keeps the branch where it is"
  end

  test "a run that could vary several skills belongs to the closest one" do
    publish("reconcile-bank-with-write-offs", "Reconcile and write off small items", [A, B, "excel.step:write-off-small-items", C])
    work(@me, [A, Z, C], times: 2)
    assert_equal [["branch", "reconcile-bank"]], Capture::Prompter.call(@me).map { |p| [p.kind, p.skill_name] }
  end

  test "save: repeating a workflow no skill covers prompts to save it; an open detected candidate is reused" do
    steps = %w[excel.step:open-expenses excel.step:filter-late excel.step:email-reminders]
    work(@me, steps, times: 3)
    p = Capture::Prompter.call(@me).sole
    assert_equal ["save", nil, steps, %w[save]], [p.kind, p.skill_name, p.steps, p.choices]

    detected = SkillCandidate.create!(signature: SkillCandidate.signature_for(steps), steps: steps, domain: "finance", occurrence_count: 3, distinct_actor_count: 1)
    c = Capture::Prompter.respond!(p, choice: "save", user: @me, title: "Chase late expense reports")
    assert_equal detected, c
    assert_equal [@me, "save", "Chase late expense reports"], [c.requested_by, c.proposal_kind, c.draft_title]
    assert_equal "chase-late-expense-reports", c.draft_name
  end

  test "people decide: dismissed prompts stay quiet, snoozed ones come back, disabled protocols never fire, thresholds hold" do
    work(@me, [A, B, C, X], times: 1)
    assert_empty Capture::Prompter.call(@me), "seen once is below the threshold"
    work(@me, [A, B, C, X], times: 1)
    p = Capture::Prompter.call(@me).sole
    Capture::Prompter.respond!(p, choice: "dismiss", user: @me)
    work(@me, [A, B, C, X], times: 2)
    assert_empty Capture::Prompter.call(@me)
    assert_raises(Capture::Prompter::Error) { Capture::Prompter.respond!(p, choice: "extend", user: @me) }

    other = make_user(domains: %w[finance])
    work(other, [A, Z, C], times: 2)
    q = Capture::Prompter.call(other).sole
    assert_raises(Capture::Prompter::Error) { Capture::Prompter.respond!(q, choice: "branch", user: @me) }
    Capture::Prompter.respond!(q, choice: "snooze", user: other)
    assert_empty other.skill_prompts.live
    travel 4.days do
      assert_equal [q], other.skill_prompts.live.to_a
    end

    third = make_user(domains: %w[finance])
    Protocol.for("branch").update!(enabled: false)
    work(third, [A, Z, C], times: 3)
    assert_empty Capture::Prompter.call(third), "a disabled branch protocol stays silent (and its variants don't become save prompts)"
    assert_raises(Capture::Prompter::Error) { Capture::Prompter.respond!(q, choice: "save", user: other) }
  end

  test "the add-in gets prompts as the person works and answers them" do
    token = AddinToken.issue!(user: @me).last
    h = { "Authorization" => "Bearer #{token}" }
    ev = ->(k, t, s) { { action: k, label: k.split(":").last.tr("-", " ").capitalize, session: s, occurred_at: t.iso8601 } }
    events = [1.day.ago, 2.hours.ago].flat_map { |t| [A, B, C, X].each_with_index.map { |k, i| ev.(k, t + i.minutes, "pane-#{t.to_i}") } }
    post api_v1_addin_events_path, params: { host: "Excel", events: events }, headers: h, as: :json
    assert_response :accepted
    assert_equal "queued", response.parsed_body["prompt_check"], "the triggers run in the background"
    assert_enqueued_jobs 1, only: PromptCheckJob
    get api_v1_addin_prompts_path, headers: h
    assert_empty response.parsed_body, "nothing until the check (and its AI evaluation) has run"

    post api_v1_addin_events_path, params: { host: "Excel", events: [ev.(A, 1.minute.ago, "pane-x")] }, headers: h, as: :json
    assert_equal "not_due", response.parsed_body["prompt_check"], "at most one check per person every 10 minutes"
    assert_enqueued_jobs 1, only: PromptCheckJob
    perform_enqueued_jobs(only: PromptCheckJob)

    get api_v1_addin_prompts_path, headers: h
    item = response.parsed_body.sole
    assert_equal ["rules", "Reconcile the bank statement"], [item["evaluated_by"], item["skill_title"]]
    assert_match(/added the same step after this skill 2 times/, item["why"])
    assert_equal [%w[extend branch], ["Flag old items"]], [item["choices"], item["added"]]
    assert_equal [A, B, C, X], item["steps"].map { |s| s["action"] }

    post respond_api_v1_addin_prompt_path(item["id"]), params: { choice: "branch", title: "Reconcile and flag" }, headers: h, as: :json
    assert_equal "accepted", response.parsed_body["status"]
    assert_equal "reconcile-and-flag", response.parsed_body.dig("candidate", "name")
    get api_v1_addin_prompts_path, headers: h
    assert_empty response.parsed_body

    travel 11.minutes do
      post api_v1_addin_events_path, params: { host: "Excel", events: [ev.(B, Time.current, "pane-y")] }, headers: h, as: :json
      assert_equal "queued", response.parsed_body["prompt_check"]
    end
  end

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

  test "the AI judges each pattern first: it can pass over noise, change the kind, and names the skill" do
    work(@me, [A, B, C, X, Y], times: 2)
    noise = FakeClaude.new(worthwhile: false, kind: "extend", confidence: 80, title: "x", description: "x", rationale: "Flagging and emailing are a separate follow-up, not reconciliation.")
    assert_empty Capture::Prompter.call(@me, client: noise)
    p = @me.skill_prompts.sole
    assert_equal ["filtered", 2], [p.status, p.evidence["filtered_at"]]
    assert_empty @me.skill_prompts.live
    assert_empty @me.notifications.where(kind: "prompt")
    payload = JSON.parse(noise.req[:messages].first[:content])
    assert_equal "extend", payload["kind"]
    assert_match(/flag old items/, payload["added_steps"].first)
    assert_equal "Reconcile the bank statement", payload.dig("existing_skill", "title")
    refute_includes noise.req[:messages].to_json, @me.name, "the AI never learns who did the work"

    work(@me, [A, B, C, X, Y], times: 1)
    assert_empty Capture::Prompter.call(@me, client: noise), "passed over until it has happened twice as often"
    good = FakeClaude.new(worthwhile: true, kind: "save", confidence: 85, title: "Chase old unmatched items",
                          description: "You flag bank items older than 30 days and email the controller.", rationale: "A distinct follow-up task.")
    work(@me, [A, B, C, X, Y], times: 1)
    p = Capture::Prompter.call(@me, client: good).sole
    assert_equal ["open", "save", %w[save], "ai"], [p.status, p.kind, p.choices, p.ai["by"]]
    assert_equal "Flag bank items older than 30 days and email the controller. Use when you need to chase old unmatched items.", p.ai["description"],
                 "the AI's description is put into the Agent Skills format (third person, says when)"
    c = Capture::Prompter.respond!(p, choice: "save", user: @me)
    assert_equal ["Chase old unmatched items", p.ai["description"]], [c.draft_title, c.draft_description]

    other = make_user(domains: %w[finance])
    work(other, [A, Z, C], times: 2)
    Protocol.for("evaluation").update!(settings: { "interval_minutes" => 10, "min_confidence" => 95 })
    assert_empty Capture::Prompter.call(other, client: FakeClaude.new(worthwhile: true, kind: "branch", confidence: 90, title: "t", description: "Does t. Use when t.", rationale: "r")),
                 "below the admins' confidence bar"
  end

  test "every skill follows Anthropic's Agent Skills format: drafts are formatted, and publishing enforces the rules" do
    std = Capture::SkillStandard
    ok = std.check(name: "reconciling-bank-statements", description: "Reconciles the bank statement against the ledger. Use when the monthly statement arrives.",
                   body: "# Reconcile\n\n## When to use\nMonthly.\n\n## Inputs\n- Statement\n\n## Steps\n1. Import\n\n## Outputs\n- Report\n\n## Checks\n- Totals tie")
    assert ok.clean?, ok.warnings.map(&:message).inspect
    bad = std.check(name: "Claude-Helper--x", description: "<b>You</b> do things", body: "---\nname: x\n---\n" + "line\n" * 501)
    assert_equal %w[name name_reserved description_xml body_frontmatter body_length], bad.errors.map(&:rule)
    assert_includes bad.warnings.map(&:rule), "when_to_use"

    n = std.normalize(name: "claude-reconcile-bank", title: "Reconcile the bank", description: "We match <i>payments</i>.", body: "---\nx: 1\n---\nSteps here")
    assert_equal ["reconcile-bank", "Match payments. Use when you need to reconcile the bank.", "# Reconcile the bank\n\nSteps here"], n.values_at(:name, :description, :body)

    c = SkillCandidate.create!(signature: "x>y", steps: %w[x y], domain: "finance", status: "drafted", draft_name: "claude-tool",
                               draft_title: "T", draft_description: "Does T. Use when T.", draft_body: "# T\n1. x")
    e = assert_raises(Capture::Publisher::Error) { Capture::Publisher.publish!(c, reviewer: @admin) }
    assert_match(/Agent Skills format: Name can't contain the reserved words/, e.message)
    e = assert_raises(Capture::Publisher::Error) { Capture::Publisher.revise!(@skill, editor: @rev, attrs: { description: "<script>x</script> Use when." }) }
    assert_match(/XML tags/, e.message)

    c.update!(draft_name: "t-procedure")
    sign_in @rev
    get skill_candidate_path(c)
    assert_includes response.body, "Agent Skills format"
    get skill_path(Capture::Publisher.publish!(c, reviewer: @admin))
    assert_includes response.body, "Has a &quot;## Steps&quot; section"
  end

  test "admins tune protocols; settings are validated" do
    sign_in @admin
    get admin_protocols_path
    assert_includes response.body, "Protocols &amp; triggers"
    patch admin_protocols_path, params: { protocols: { save: { enabled: "1", min_repeats: "5", min_steps: "4", lookback_days: "7", snooze_days: "2" },
                                                       extend: { enabled: "0" }, branch: { enabled: "1" }, rest_stop: { enabled: "1", daily: "0", keep_auto: "10" } } }
    assert_redirected_to admin_protocols_path
    assert_equal [5, 4], [Protocol.for("save")["min_repeats"], Protocol.for("save")["min_steps"]]
    assert_not Protocol.for("extend").enabled
    assert_equal [false, 10], [Protocol.for("rest_stop")["daily"], Protocol.for("rest_stop")["keep_auto"]]
    patch admin_protocols_path, params: { protocols: { save: { enabled: "1", min_repeats: "0" } } }
    assert_response :unprocessable_entity
    assert_equal 5, Protocol.for("save").reload["min_repeats"]
    sign_in @me
    get admin_protocols_path
    assert_redirected_to root_path
  end

  # ---------- rest stops ----------

  test "rest stops are automatic, skip unchanged states, and revert everything: text, steps, directions, resources and fields" do
    first = RestStop.where(skill_name: "reconcile-bank").sole
    assert_equal ["published", 1], [first.reason, first.skill_version]
    assert_nil Capture::RestStops.capture!(@skill, reason: "daily").then { |s| s == first ? nil : s }, "nothing changed: no new rest stop"

    folder = ResourceFolder.create!(name: "Finance")
    wb = folder.resources.new(name: "Recs workbook", uploaded_by: @admin).tap { |r| r.attach_file(StringIO.new("x"), filename: "r.xlsx", content_type: "application/octet-stream"); r.save! }
    SkillResource.create!(skill_name: "reconcile-bank", resource: wb)
    place = Capture::Directions.find("road:reconcile-bank")
    Capture::Directions.save!(place, body: "Original road directions", user: @rev)
    good = Capture::RestStops.capture!(@skill, reason: "manual", kind: "manual", user: @rev, label: "Known good")
    assert_equal ["Original road directions"], good.directions.map { |d| d["body"] }
    assert_equal ["Recs workbook"], good.snapshot["resources"].map { |r| r["name"] }

    # Things change: a new version with other steps, new directions, a resource detached, another field.
    v2 = Capture::Publisher.revise!(@skill, editor: @rev, attrs: { body: "Totally different", workflow: [A, C], change_note: "shortcut" })
    Capture::Directions.save!(Capture::Directions.find("road:reconcile-bank"), body: "Changed directions", user: @rev)
    SkillResource.delete_all
    SkillClassification.for("reconcile-bank").set_fields!([Field.find_by!(path: "legal")], source: "user")

    sign_in @me
    post revert_rest_stop_path(good)
    assert_redirected_to rest_stop_path(good)
    assert_match(/can't revert/, flash[:alert])
    assert_equal 2, Skill.current("reconcile-bank").version, "a member can't revert"

    sign_in @rev
    get rest_stop_path(good)
    assert_includes response.body, "Reverting changes"
    assert_includes response.body, "✓ Checksum verified"
    post revert_rest_stop_path(good)
    v3 = Skill.current("reconcile-bank")
    assert_equal [3, v2, "1. Import\n2. Match\n3. Investigate", [A, B, C]], [v3.version, v3.parent_skill, v3.body, v3.source["workflow"]]
    assert_match(/Reverted to rest stop ##{good.id}/, v3.source["change_note"])
    assert_equal "Original road directions", Waypoint.find_by!(key: "road:reconcile-bank").body
    assert_equal [wb.id], SkillResource.where(skill_name: "reconcile-bank").pluck(:resource_id)
    assert_equal good.snapshot["fields"], SkillClassification.for("reconcile-bank").field_paths
    before = RestStop.where(skill_name: "reconcile-bank", reason: "before_revert").sole
    assert before.pinned
    assert_equal "Totally different", before.snapshot["body"], "the state before the revert is kept, so a revert can be undone"
    assert RestStop.exists?(skill_name: "reconcile-bank", reason: "reverted")
    assert AuditLog.exists?(action: "rest_stop.reverted")
  end

  test "people save rest stops by hand, pin them, and download them; automatic ones are pruned to the protocol's limit" do
    sign_in @rev
    post skill_rest_stops_path(@skill), params: { label: "Before quarter end" }
    stop = RestStop.recent.first
    assert_equal ["manual", "Before quarter end", @rev], [stop.kind, stop.label, stop.created_by]
    get skill_path(@skill)
    assert_includes response.body, "Before quarter end"
    patch rest_stop_path(stop), params: { pinned: true }
    assert stop.reload.pinned
    get rest_stop_path(stop, format: :json)
    assert_equal stop.checksum, JSON.parse(response.body)["checksum"]

    outsider = make_user(domains: %w[legal])
    sign_in outsider
    post skill_rest_stops_path(@skill)
    assert_equal 2, RestStop.where(skill_name: @skill.name).count

    Protocol.for("rest_stop").update!(settings: { "daily" => true, "keep_auto" => 3 })
    6.times { |i| Capture::RestStops.capture!(@skill, reason: "daily", snapshot: Capture::RestStops.snapshot(@skill).merge("body" => "v#{i}")) }
    assert_equal 3, RestStop.where(skill_name: @skill.name, kind: "auto", pinned: false).count
    assert RestStop.exists?(stop.id), "manual rest stops are never pruned"
  end

  test "redundancy: every rest stop is mirrored to disk, and verify repairs the database or the mirror from the other" do
    stop = RestStop.where(skill_name: "reconcile-bank").sole
    file = Capture::RestStops.path_for(stop)
    assert file.exist?
    assert_equal stop.checksum, JSON.parse(file.read)["checksum"]

    stop.update_columns(snapshot: stop.snapshot.merge("body" => "corrupted"))
    assert_not stop.reload.intact?
    assert_equal 1, Capture::RestStops.verify!(repair: false)[:restored_from_mirror]
    assert_not stop.reload.intact?, "a dry run changes nothing"
    assert_equal 1, Capture::RestStops.verify![:restored_from_mirror]
    assert stop.reload.intact?

    file.delete
    assert_equal 1, Capture::RestStops.verify![:mirror_repaired]
    assert file.exist?

    id = stop.id
    stop.delete
    assert_equal 1, Capture::RestStops.verify![:rows_restored]
    assert RestStop.find(id).intact?

    assert_equal 0, Capture::RestStops.sweep!, "the daily sweep skips skills that didn't change"
    SkillClassification.for("reconcile-bank").update!(apps: %w[Excel Word])
    assert_equal 1, Capture::RestStops.sweep!
  end

  test "agents read rest stops of shared skills only" do
    _src, token = make_source(name: "Agent")
    h = { "Authorization" => "Bearer #{token}" }
    get api_v1_skill_rest_stops_path("reconcile-bank"), headers: h
    list = response.parsed_body
    assert_equal ["published"], list.map { |s| s["reason"] }
    get api_v1_rest_stop_path(list.first["id"]), headers: h
    assert_equal [A, B, C], response.parsed_body.dig("snapshot", "workflow")

    @skill.update!(stage: "local")
    get api_v1_skill_rest_stops_path("reconcile-bank"), headers: h
    assert_response :not_found
  end
end
