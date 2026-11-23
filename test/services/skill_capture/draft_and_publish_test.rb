require "test_helper"

class SkillCapture::DraftAndPublishTest < ActiveSupport::TestCase
  setup do
    @ops = make_user(role: "ops")
    @sales = make_user(role: "sales")
  end

  test "template drafter produces a valid Agent Skills draft without an LLM" do
    c = drafted_candidate(contributors: [@ops]).tap { |x| x.update!(status: "detected", draft_body: nil) }
    ENV["SKILL_CAPTURE_LLM"] = "off"
    SkillCapture::DraftGenerator.call(c)
    c.reload
    assert_equal "drafted", c.status
    assert_equal "template", c.draft_generator
    assert_match Skill::NAME_FORMAT, c.draft_name
    assert_operator c.draft_description.length, :<=, 1024
    assert_includes c.draft_body, "Release the run"
    assert_includes c.draft_body, "## Steps"
  ensure
    ENV.delete("SKILL_CAPTURE_LLM")
  end

  test "claude drafter sends only workflow structure and parses structured output" do
    c = drafted_candidate(contributors: [@ops])
    fake = FakeAnthropic.new(stop_reason: :end_turn, json: {
      name: "Run A Production Batch!", title: "Run a production batch", description: "Do the thing.",
      tags: ["Ops", "production"], inputs: ["Scheduled run"], outputs: ["Finished-good lot"], body: "# Steps\n1. Release"
    })
    out = SkillCapture::ClaudeDrafter.call(c, client: fake)
    assert_equal "run-a-production-batch", out[:name]
    assert_equal %w[ops production], out[:tags]

    req = fake.last_request
    assert_equal "claude-opus-5-5", req[:model]
    assert_equal :default, req[:fallbacks]
    assert_equal :json_schema, req[:output_config][:format][:type]
    sent = JSON.parse(req[:messages].first[:content])
    assert_equal c.steps, sent["steps"].map { |s| s["app_action"] }
    refute_includes req[:messages].to_json, @ops.email
    refute_includes req[:messages].to_json, @ops.first_name
  end

  test "claude refusal falls back to the template drafter" do
    c = drafted_candidate(contributors: [@ops])
    fake = FakeAnthropic.new(stop_reason: :refusal, json: {})
    assert_raises(SkillCapture::ClaudeDrafter::DraftError) { SkillCapture::ClaudeDrafter.call(c, client: fake) }
  end

  test "publishing creates v1 with provenance; a later candidate with the same name becomes v2" do
    c = drafted_candidate(contributors: [@ops, @sales])
    skill = SkillCapture::Publisher.publish!(c, reviewer: @ops)

    assert_equal 1, skill.version
    assert_equal "published", skill.status
    assert_equal @ops, skill.published_by
    assert_equal c.steps, skill.source["workflow"]
    assert_equal [@ops.display_name, @sales.display_name].sort, skill.source["contributors"].sort
    assert_equal "approved", c.reload.status
    assert_equal skill, c.skill
    assert AuditLog.exists?(action: "skill.published", subject: skill)
    assert Notification.exists?(user: @sales, kind: "skill_published"), "contributors hear their work was captured"

    c2 = drafted_candidate(steps: %w[production_runs#release production_runs#complete], contributors: [@ops])
    v2 = SkillCapture::Publisher.publish!(c2, reviewer: @ops)
    assert_equal 2, v2.version
    assert_equal skill, v2.parent_skill
    assert_equal "superseded", skill.reload.status
  end

  test "only the workflow's domain owners or admins can publish" do
    c = drafted_candidate(contributors: [@ops])
    err = assert_raises(SkillCapture::Publisher::Error) { SkillCapture::Publisher.publish!(c, reviewer: @sales) }
    assert_match(/admin\/ops/, err.message)
    assert SkillCapture::Publisher.publish!(c, reviewer: make_user(role: "admin"))
  end

  test "revise creates a new version; renaming forks with lineage" do
    skill = SkillCapture::Publisher.publish!(drafted_candidate(contributors: [@ops]), reviewer: @ops)

    v2 = SkillCapture::Publisher.revise!(skill, editor: @ops, attrs: { body: "# Updated", change_note: "new line layout" })
    assert_equal [skill.name, 2], [v2.name, v2.version]
    assert_equal "superseded", skill.reload.status
    assert_equal "new line layout", v2.source["change_note"]

    fork = SkillCapture::Publisher.revise!(v2, editor: @ops, attrs: { name: "run-a-canning-batch", title: "Run a canning batch" })
    assert_equal 1, fork.version
    assert_equal v2, fork.parent_skill
    assert_equal "published", v2.reload.status, "forking leaves the original in place"
    assert_equal [fork, v2, skill], fork.lineage

    assert_raises(SkillCapture::Publisher::Error) { SkillCapture::Publisher.revise!(fork, editor: @sales, attrs: { body: "x" }) }
  end

  test "SKILL.md has Agent Skills frontmatter and can be exported to a skill repository" do
    skill = SkillCapture::Publisher.publish!(drafted_candidate(contributors: [@ops]), reviewer: @ops)
    md = skill.to_skill_md
    _, front, body = md.split(/^---\s*$/, 3)
    meta = YAML.safe_load(front)
    assert_equal skill.name, meta["name"]
    assert_equal skill.description, meta["description"]
    assert_equal "1", meta.dig("metadata", "version")
    assert_nil meta.dig("metadata", "source", "contributor_ids"), "internal user ids stay out of exported files"
    assert_includes body, "# Run a production batch"

    Dir.mktmpdir do |dir|
      path = SkillCapture::SkillFile.export(skill, dir: dir)
      assert_equal File.join(dir, skill.name, "SKILL.md"), path.to_s
      assert_equal md, File.read(path)
    end
  end

  class FakeAnthropic
    attr_reader :last_request
    Block = Struct.new(:type, :text)
    Msg = Struct.new(:stop_reason, :stop_details, :content)

    def initialize(stop_reason:, json:)
      @stop_reason = stop_reason
      @json = json
    end

    def beta = self
    def messages = self

    def create(**req)
      @last_request = req
      Msg.new(@stop_reason, nil, [Block.new(:text, @json.to_json)])
    end
  end
end
