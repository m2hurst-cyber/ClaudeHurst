require "test_helper"

class FrontDoorExtrasTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = make_user(domains: %w[finance])
    @reviewer = make_user(role: "reviewer", domains: %w[finance])
    @admin = make_user(role: "admin")
  end

  def publish(name: "bill-a-new-order")
    steps = %W[crm.open:#{name} erp.create:#{name} erp.send:#{name}]
    Capture::Publisher.publish!(drafted_candidate(name: name, steps: steps), reviewer: @reviewer)
  end

  # ---------- help in the one box ----------

  test "asking the front door how something works finds the help" do
    result = Capture::Find.call("how do I branch a skill", viewer: @user)
    assert_includes result[:groups].keys, "help"
    titles = result[:groups]["help"].map(&:title)
    assert titles.any? { |t| t.match?(/branch/i) }, "expected a branch guide or answer, got #{titles.inspect}"
  end

  test "a help hit links to the guide it came from" do
    hits = Capture::Find.call("granularity", viewer: @user)[:groups]["help"]
    assert hits.any? { |h| h.url == help_guide_path("granularity") }
  end

  test "the help never outranks the thing itself" do
    candidate = drafted_candidate(name: "send-a-skill", steps: %w[ui.open:transfer ui.pick:skill ui.send:skill])
    candidate.update!(draft_title: "Send a skill", draft_description: "Sends a skill straight to a coworker.")
    Capture::Publisher.publish!(candidate, reviewer: @reviewer)
    result = Capture::Find.call("send a skill", viewer: @user)
    best = result[:best]
    refute_equal "help", best.group, "a question about doing something should lead with the thing that does it"
  end

  test "the front door renders help results" do
    sign_in @user
    get find_path, params: { q: "how does review work" }
    assert_response :success
    assert_select "h2", /Help and answers/i
  end

  # ---------- the shortcuts ----------

  test "the front door offers the map, the library and a way to write one" do
    sign_in @user
    get root_path
    assert_select "nav[aria-label=Shortcuts]" do
      assert_select "a[href=?]", skill_map_path
      assert_select "a[href=?]", skills_path
      assert_select "a[href=?]", new_skill_candidate_path
    end
    assert_select "nav[aria-label=Shortcuts] svg[aria-hidden=true]", 3
  end

  # ---------- provenance in the interface ----------

  test "a skill shows its identity and links to its provenance" do
    skill = publish
    sign_in @user
    get skill_path(skill)
    assert_response :success
    assert_select "a[href=?]", provenance_skill_path(skill)
    assert_match skill.short_hash, response.body
  end

  test "the provenance page shows the chain and whether it still holds" do
    skill = publish
    Capture::Provenance.anchor!(Date.current)
    sign_in @user

    get provenance_skill_path(skill)
    assert_response :success
    assert_match skill.content_hash, response.body
    assert_select "ol li", /Published/
    assert_match(/holds/, response.body)
    assert_match(/the stored hash matches/, response.body)
  end

  test "a tampered entry is reported on the page, not hidden" do
    skill = publish
    ProvenanceEntry.last.update_column(:payload, { "candidate_id" => 0 })
    sign_in @user
    get provenance_skill_path(skill)
    assert_match(/⚠/, response.body)
  end

  test "only an admin is told about the whole chain" do
    skill = publish
    sign_in @user
    get provenance_skill_path(skill)
    assert_no_match(/Whole chain/, response.body)

    sign_in @admin
    get provenance_skill_path(skill)
    assert_match(/Whole chain/, response.body)
  end

  test "the manifest is downloadable and checks out" do
    skill = publish
    sign_in @user
    get provenance_skill_path(skill, format: :json)
    assert_response :success
    manifest = JSON.parse(response.body)
    assert_equal skill.content_hash, manifest["content_hash"]
    entry = manifest["entries"].first
    assert_equal entry["hash"], Capture::Canonical.digest(entry.except("hash"))
  end

  test "a transfer shows what was pinned, by the same identity" do
    skill = publish
    transfer = SkillTransfer.offer!(sender: @reviewer, recipient: @user, names: [skill.name], price: 0)
    sign_in @user
    get transfer_path(transfer)
    assert_response :success
    assert_match skill.content_hash.first(12), response.body
    assert_select "a[href=?]", provenance_skill_path(skill)
  end

  # ---------- a person's own settings ----------

  test "someone can ask for fewer, larger prompts without an admin" do
    Protocol.for("granularity").update!(settings: { "level" => 3 })
    sign_in @user

    get settings_path
    assert_response :success
    assert_select "input[type=radio][name=granularity][value=inherit][checked]"

    patch settings_path, params: { granularity: "5" }
    assert_redirected_to settings_path
    assert_equal 5, Capture::Granularity.level_for(domain: "finance", user: @user.reload)
    assert_equal 3, Capture::Granularity.level_for(domain: "finance"), "only their own prompts change"
  end

  test "they can hand it back to their area" do
    GranularityOverride.set!("domain", "finance", 4)
    GranularityOverride.set!("user", @user.id, 1)
    sign_in @user

    patch settings_path, params: { granularity: "inherit" }
    assert_nil GranularityOverride.find_by(scope: "user", scope_key: @user.id.to_s)
    assert_equal 4, Capture::Granularity.level_for(domain: "finance", user: @user.reload)
  end

  test "settings shows where the tour got to" do
    sign_in @user
    get settings_path
    assert_match(/of \d+ steps done/, response.body)
    assert_select "a[href=?]", tour_path
  end

  # ---------- the desk, for someone who actually has work waiting ----------

  test "the front door does not fall over for someone with live prompts" do
    SkillPrompt.create!(user: @user, kind: "save", steps: %w[a.one b.two c.three],
                        fingerprint: SecureRandom.hex(8), occurrences: 4, status: "open")
    sign_in @user

    get root_path
    assert_response :success
    assert_match(/Save them as a skill/, response.body)
  end

  test "the desk survives every kind of waiting work at once" do
    skill = publish
    SkillPrompt.create!(user: @user, kind: "extend", skill_name: skill.name, steps: %w[a.one],
                        evidence: { "added" => %w[x.two] }, fingerprint: SecureRandom.hex(8), occurrences: 3)
    SkillTransfer.offer!(sender: @reviewer, recipient: @user, names: [skill.name], price: 0)
    sign_in @user

    get root_path
    assert_response :success
    assert_match(/Extend the skill/, response.body)
  end
end
