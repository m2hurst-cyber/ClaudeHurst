require "test_helper"

class GranularityTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup { @source, = make_source }

  # Three identical runs of one long, rigid procedure. Nothing inside it ever appears
  # anywhere else, so every sub-sequence has exactly one set of surroundings.
  def rigid_flow
    3.times do |i|
      perform_workflow(@source, "u-1", %w[fin.open:tb fin.map:accounts fin.flag:variance fin.draft:commentary fin.review:pack fin.send:pack],
                       start: (10 - i).hours.ago, session: "rigid-#{i}")
    end
  end

  # The same two steps done inside three different larger jobs: a building block.
  def reused_block
    %w[alpha beta gamma].each_with_index do |ctx, i|
      perform_workflow(@source, "u-1", ["#{ctx}.open:file", "eq.pull:betas", "eq.unlever:betas", "#{ctx}.close:file"],
                       start: (40 - i).hours.ago, session: "ctx-#{i}")
    end
  end

  def detect(level, base: 1)
    Capture::WorkflowDetector.new(level: level, min_occurrences: base).detect
  end

  test "atomic keeps a block that is reused in different surroundings" do
    reused_block
    patterns = detect(1)
    assert_includes patterns.map(&:steps), %w[eq.pull:betas eq.unlever:betas]
    assert_equal 3, patterns.find { |p| p.steps == %w[eq.pull:betas eq.unlever:betas] }.context_count
  end

  test "atomic rejects a fragment that only ever appears inside one larger job" do
    rigid_flow
    assert_empty detect(1), "a rigid procedure has no reusable blocks, only fragments"
  end

  test "end to end keeps the whole procedure the fine setting threw away" do
    rigid_flow
    patterns = detect(4)
    assert_equal 1, patterns.size
    assert_equal 6, patterns.first.steps.size
    assert_equal 3, patterns.first.occurrences
  end

  test "the coarse setting finds nothing in work that is only ever short" do
    reused_block
    assert_empty detect(5), "nothing here is five steps long and repeated"
  end

  test "the same events give a different answer at each end of the slider" do
    rigid_flow
    reused_block
    fine = detect(1).map(&:steps)
    coarse = detect(4).map(&:steps)

    assert_includes fine, %w[eq.pull:betas eq.unlever:betas]
    refute_includes coarse, %w[eq.pull:betas eq.unlever:betas]
    assert coarse.any? { |s| s.size == 6 }
    assert fine.none? { |s| s.size > 3 }
  end

  test "a fine setting asks for more repetition before it believes a pattern" do
    assert_equal 6, Capture::Granularity.min_occurrences(1, base: 3)
    assert_equal 3, Capture::Granularity.min_occurrences(3, base: 3)
    assert_equal 2, Capture::Granularity.min_occurrences(5, base: 3)
    assert_equal 2, Capture::Granularity.min_occurrences(5, base: 1), "never below two"
  end

  test "a person's setting beats their area's, and an area's beats the firm's" do
    Protocol.for("granularity").update!(settings: { "level" => 3 })
    user = make_user(domains: %w[tax])

    assert_equal 3, Capture::Granularity.level_for(domain: "tax", user: user)
    GranularityOverride.set!("domain", "tax", 5)
    assert_equal 5, Capture::Granularity.level_for(domain: "tax", user: user)
    GranularityOverride.set!("user", user.id, 1)
    assert_equal 1, Capture::Granularity.level_for(domain: "tax", user: user)
    assert_equal 5, Capture::Granularity.level_for(domain: "tax"), "the person's setting is only theirs"

    GranularityOverride.set!("user", user.id, nil)
    assert_equal 5, Capture::Granularity.level_for(domain: "tax", user: user)
  end

  test "detection runs over the widest window any area asks for" do
    Protocol.for("granularity").update!(settings: { "level" => 3 })
    assert_equal({ min_steps: 2, max_steps: 6 }, Capture::Granularity.envelope)
    GranularityOverride.set!("domain", "research", 1)
    GranularityOverride.set!("domain", "tax", 5)
    assert_equal({ min_steps: 2, max_steps: 14 }, Capture::Granularity.envelope)
  end

  test "each area is judged at its own setting in one pass" do
    perform_workflow(@source, "u-1", %w[tax.open:return tax.import:w2 tax.check:basis tax.file:return], start: 5.hours.ago, session: "t1", domain: "tax")
    perform_workflow(@source, "u-1", %w[tax.open:return tax.import:w2 tax.check:basis tax.file:return], start: 4.hours.ago, session: "t2", domain: "tax")
    GranularityOverride.set!("domain", "tax", 4)
    Protocol.for("granularity").update!(settings: { "level" => 1 })

    # The firm is set to atomic, which would reject this rigid four-step run; tax is not.
    patterns = Capture::WorkflowDetector.new(min_occurrences: 1).detect
    assert_equal 1, patterns.size
    assert_equal 4, patterns.first.steps.size
  end

  test "the preview costs every setting against the events already collected" do
    rigid_flow
    preview = Capture::Granularity.preview(levels: [1, 4])

    assert_equal 0, preview[1][:count]
    assert_operator preview[4][:count], :>=, 1
    assert_equal "End to end", Capture::Granularity.preview(levels: [5])[5][:label]
    assert preview[4][:samples].first[:title].present?
  end

  test "the slider and its per-area overrides save from the admin page" do
    admin = make_user(role: "admin")
    Skill.create!(name: "a-skill", title: "A skill", description: "x" * 40, body: "body", domain: "tax", published_at: Time.current)
    sign_in admin

    get admin_protocols_path
    assert_response :success
    assert_select "input[type=range][name='protocols[granularity][level]']"
    assert_select "select[name='granularity_by_area[tax]']"

    patch admin_protocols_path, params: {
      protocols: Protocol.all_keys.to_h { |p| [p.key, p.settings.merge("enabled" => "1")] }.merge("granularity" => { "level" => "5", "enabled" => "1" }),
      granularity_by_area: { "tax" => "1" }
    }
    assert_redirected_to admin_protocols_path
    assert_equal 5, Capture::Granularity.firm_level
    assert_equal 1, Capture::Granularity.level_for(domain: "tax")
  end

  test "the preview endpoint answers with every level" do
    sign_in make_user(role: "admin")
    get preview_admin_protocols_path
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal %w[1 2 3 4 5], body.keys.sort
    assert body["3"].key?("count")
  end
end
