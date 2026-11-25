require "test_helper"

class ProvenanceTest < ActionDispatch::IntegrationTest
  setup do
    @reviewer = make_user(role: "reviewer", domains: %w[finance])
    @admin = make_user(role: "admin")
  end

  def publish(name: "bill-a-new-order")
    steps = %W[crm.open:#{name} erp.create:#{name} erp.send:#{name}]
    Capture::Publisher.publish!(drafted_candidate(name: name, steps: steps), reviewer: @reviewer)
  end

  test "a skill's content hash is its identity, and ignores everything that isn't the skill" do
    skill = publish
    assert_match(/\A[0-9a-f]{64}\z/, skill.content_hash)
    before = skill.content_hash

    # Promoting, voting on or re-timestamping a skill does not change what it is.
    skill.update!(stage: "market", stage_changed_at: Time.current, market_audience: "global")
    assert_equal before, skill.reload.content_hash

    # Changing a word of the body does.
    skill.update!(body: skill.body + "\n4. File it")
    refute_equal before, skill.content_hash
  end

  test "the same content gives the same hash from a different record" do
    a = publish
    twin = Skill.new(a.attributes.except("id", "created_at", "updated_at", "content_hash"))
    assert_equal a.content_hash, twin.compute_content_hash
  end

  test "publishing, revising and promoting each append a link to the chain" do
    skill = publish
    assert_equal %w[skill.published], Capture::Provenance.history(skill.name).pluck(:event)

    revised = Capture::Publisher.revise!(skill, editor: @reviewer, attrs: { body: skill.body + "\n4. File it" })
    assert_equal %w[skill.published skill.revised], Capture::Provenance.history(skill.name).pluck(:event)
    assert_equal revised.content_hash, Capture::Provenance.history(skill.name).last.content_hash

    PromotionPolicy.current.update!(initial_stage: "local")
    local = publish(name: "second-skill")
    promotion = Promotion.create!(skill_name: local.name, skill_version: local.version, from_stage: "local",
                                  to_stage: "firm", requested_by: @reviewer, checks: [])
    Capture::Promotions.new(@admin).approve!(promotion, notes: "fine", waive: true)
    assert_equal %w[skill.published skill.promoted], Capture::Provenance.history(local.name).pluck(:event)
  end

  test "each entry commits to the one before it" do
    publish
    publish(name: "second-skill")
    entries = ProvenanceEntry.chronological.to_a
    assert_operator entries.size, :>=, 2
    assert_equal ProvenanceEntry::GENESIS, entries.first.prev_hash
    entries.each_cons(2) { |a, b| assert_equal a.entry_hash, b.prev_hash }
    assert Capture::Provenance.verify.ok
  end

  test "editing history is caught, and the verdict says where" do
    publish
    publish(name: "second-skill")
    victim = ProvenanceEntry.chronological.first
    victim.update_column(:payload, { "candidate_id" => 99_999 })

    verdict = Capture::Provenance.verify
    refute verdict.ok
    assert_equal victim.sequence, verdict.broken_at
    assert_match(/contents do not match/, verdict.reason)
  end

  test "removing an entry breaks the links after it" do
    publish
    publish(name: "second-skill")
    publish(name: "third-skill")
    ProvenanceEntry.chronological.second.delete

    verdict = Capture::Provenance.verify
    refute verdict.ok
    assert_match(/previous entry/, verdict.reason)
  end

  test "an anchor commits to the day and notices when the day changes underneath it" do
    publish
    publish(name: "second-skill")
    anchor = Capture::Provenance.anchor!(Date.current)

    assert_equal 2, anchor.entry_count
    assert anchor.holds?
    assert_equal anchor.root_hash, Capture::Canonical.merkle_root(ProvenanceEntry.where(event: %w[skill.published]).chronological.pluck(:entry_hash))

    # The anchor is mirrored outside the database.
    mirrored = Pathname(ENV["SKILL_CAPTURE_PROVENANCE_DIR"]).join("anchor-#{Date.current.iso8601}.json")
    assert mirrored.exist?
    assert_equal anchor.root_hash, JSON.parse(mirrored.read)["root"]

    ProvenanceEntry.chronological.first.update_column(:entry_hash, "0" * 64)
    refute anchor.reload.holds?
  end

  test "anchoring the same day twice is a no-op" do
    publish
    first = Capture::Provenance.anchor!(Date.current)
    assert_equal first.id, Capture::Provenance.anchor!(Date.current).id
  end

  test "the manifest carries enough for someone outside to check it" do
    skill = publish
    Capture::Provenance.anchor!(Date.current)
    manifest = Capture::Provenance.manifest(skill)

    assert_equal skill.content_hash, manifest["content_hash"]
    assert_equal 1, manifest["entries"].size
    entry = manifest["entries"].first
    assert_equal entry["hash"], Capture::Canonical.digest(entry.except("hash"))
    assert_equal 1, manifest["anchors"].size
  end

  test "a transfer records what was delivered, by content hash" do
    skill = publish
    sender = @reviewer
    recipient = make_user
    transfer = SkillTransfer.offer!(sender: sender, recipient: recipient, names: [skill.name], price: 0)
    transfer.accept!(by: recipient)

    entry = ProvenanceEntry.where(event: "skill.transferred").last
    assert_equal skill.content_hash, entry.content_hash
    assert_equal "user:#{sender.id}", entry.actor_key
    assert Capture::Provenance.verify.ok
  end

  test "canonical form is stable whatever order the keys arrive in" do
    a = { "b" => 1, "a" => { "d" => [3, 2], "c" => true } }
    b = { "a" => { "c" => true, "d" => [3, 2] }, "b" => 1 }
    assert_equal Capture::Canonical.digest(a), Capture::Canonical.digest(b)
    refute_equal Capture::Canonical.digest(a), Capture::Canonical.digest({ "b" => 1, "a" => { "d" => [2, 3], "c" => true } })
  end

  test "a merkle root changes if any leaf changes, and an odd leaf still carries up" do
    hashes = 5.times.map { |i| Digest::SHA256.hexdigest(i.to_s) }
    root = Capture::Canonical.merkle_root(hashes)
    assert_match(/\A[0-9a-f]{64}\z/, root)
    assert_equal root, Capture::Canonical.merkle_root(hashes)
    refute_equal root, Capture::Canonical.merkle_root(hashes.reverse)
    assert_nil Capture::Canonical.merkle_root([])
  end
end
