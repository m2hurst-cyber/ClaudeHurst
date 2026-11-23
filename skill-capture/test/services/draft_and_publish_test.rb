require "test_helper"

class DraftAndPublishTest < ActiveSupport::TestCase
  setup do
    @finance = make_user(role: "reviewer", domains: ["finance"])
    @other = make_user(role: "reviewer", domains: ["support"])
  end

  test "template drafter produces a valid draft from action labels" do
    ActionDefinition.create!(key: "crm.open:account", label: "Open the customer account")
    c = drafted_candidate.tap { |x| x.update!(status: "detected", draft_body: nil) }
    Capture::DraftGenerator.call(c)
    c.reload
    assert_equal ["drafted", "template"], [c.status, c.draft_generator]
    assert_match Skill::NAME_FORMAT, c.draft_name
    assert_operator c.draft_description.length, :<=, 1024
    assert_includes c.draft_body, "1. Open the customer account."
  end

  test "claude drafter sends workflow structure only and parses structured output" do
    c = drafted_candidate
    fake = FakeAnthropic.new(:end_turn, name: "Bill A New Order!", title: "Bill a new order", description: "d",
                                        tags: ["Finance", "billing"], inputs: ["Account"], outputs: ["Invoice"], body: "# Steps")
    out = Capture::ClaudeDrafter.call(c, client: fake)
    assert_equal "bill-a-new-order", out[:name]
    assert_equal %w[finance billing], out[:tags]

    req = fake.last_request
    assert_equal "claude-opus-5-5", req[:model]
    assert_equal :default, req[:fallbacks]
    assert_equal :json_schema, req.dig(:output_config, :format, :type)
    sent = JSON.parse(req[:messages].first[:content])
    assert_equal c.steps, sent["steps"].map { |s| s["action"] }
    refute_includes req.to_json, "Person A"
    refute_includes req.to_json, "a-1"
  end

  test "claude refusal raises so the generator can fall back" do
    assert_raises(Capture::ClaudeDrafter::DraftError) do
      Capture::ClaudeDrafter.call(drafted_candidate, client: FakeAnthropic.new(:refusal))
    end
  end

  test "generator falls back to the template when Claude errors" do
    c = drafted_candidate
    ENV["SKILL_CAPTURE_LLM"] = "on"
    ENV["ANTHROPIC_API_KEY"] = "test-key"
    Capture::ClaudeDrafter.stub(:call, ->(*) { raise Capture::ClaudeDrafter::DraftError, "boom" }) do
      Capture::DraftGenerator.call(c)
    end
    assert_equal "template", c.reload.draft_generator
  ensure
    ENV["SKILL_CAPTURE_LLM"] = "off"
    ENV.delete("ANTHROPIC_API_KEY")
  end

  test "publish creates v1 with provenance; reusing the name later creates v2" do
    c = drafted_candidate
    skill = Capture::Publisher.publish!(c, reviewer: @finance)
    assert_equal [1, "published", @finance], [skill.version, skill.status, skill.published_by]
    assert_equal c.steps, skill.source["workflow"]
    assert_equal ["Person A", "Person B"], skill.source["contributors"]
    assert_equal ["approved", skill], [c.reload.status, c.skill]
    assert AuditLog.exists?(action: "skill.published", subject: skill)

    v2 = Capture::Publisher.publish!(drafted_candidate(steps: %w[crm.open:account erp.send:invoice]), reviewer: @finance)
    assert_equal [2, skill], [v2.version, v2.parent_skill]
    assert_equal "superseded", skill.reload.status
  end

  test "only the area's reviewers or admins can publish" do
    c = drafted_candidate
    assert_raises(Capture::Publisher::Error) { Capture::Publisher.publish!(c, reviewer: @other) }
    assert_raises(Capture::Publisher::Error) { Capture::Publisher.publish!(c, reviewer: make_user(role: "member")) }
    assert Capture::Publisher.publish!(c, reviewer: make_user(role: "admin"))
  end

  test "revise creates versions; renaming forks with lineage" do
    skill = Capture::Publisher.publish!(drafted_candidate, reviewer: @finance)
    v2 = Capture::Publisher.revise!(skill, editor: @finance, attrs: { body: "# New", change_note: "new ERP screen" })
    assert_equal [skill.name, 2, "new ERP screen"], [v2.name, v2.version, v2.source["change_note"]]
    assert_equal "superseded", skill.reload.status

    fork = Capture::Publisher.revise!(v2, editor: @finance, attrs: { name: "bill-a-repeat-order" })
    assert_equal [1, v2], [fork.version, fork.parent_skill]
    assert_equal "published", v2.reload.status
    assert_equal [fork, v2, skill], fork.lineage

    assert_raises(Capture::Publisher::Error) { Capture::Publisher.revise!(fork, editor: @other, attrs: { body: "x" }) }
    assert_raises(Capture::Publisher::Error) { Capture::Publisher.revise!(skill, editor: @finance, attrs: { body: "x" }) }
  end

  test "SKILL.md has Agent Skills frontmatter, no internal ids, and exports to a directory" do
    skill = Capture::Publisher.publish!(drafted_candidate, reviewer: @finance)
    md = skill.to_skill_md
    _, front, body = md.split(/^---\s*$/, 3)
    meta = YAML.safe_load(front)
    assert_equal [skill.name, skill.description], meta.values_at("name", "description")
    assert_equal "1", meta.dig("metadata", "version")
    assert_nil meta.dig("metadata", "source", "contributor_keys")
    assert_includes body, "# Bill a new order"

    Dir.mktmpdir do |dir|
      path = Capture::SkillFile.export(skill, dir: dir)
      assert_equal md, File.read(path)
    end
  end

  test "publish-rate alert notifies admins" do
    admin = make_user(role: "admin")
    ENV["SKILL_CAPTURE_PUBLISH_ALERT_PER_HOUR"] = "1"
    Capture::Publisher.publish!(drafted_candidate(name: "one"), reviewer: @finance)
    Capture::Publisher.publish!(drafted_candidate(steps: %w[a.b c.d], name: "two"), reviewer: @finance)
    assert Notification.exists?(user: admin, kind: "alert")
  ensure
    ENV.delete("SKILL_CAPTURE_PUBLISH_ALERT_PER_HOUR")
  end

  class FakeAnthropic
    attr_reader :last_request
    Block = Struct.new(:type, :text)
    Msg = Struct.new(:stop_reason, :stop_details, :content)

    def initialize(stop_reason, **json)
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
