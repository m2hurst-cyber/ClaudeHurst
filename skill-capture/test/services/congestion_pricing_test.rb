require "test_helper"

class CongestionPricingTest < ActiveSupport::TestCase
  STEPS = %w[erp.receive:invoice erp.match:po erp.post:invoice].freeze

  setup do
    @source, = make_source
    @reviewer = make_user(role: "reviewer", domains: %w[finance], name: "Rae")
    @other_reviewer = make_user(role: "reviewer", domains: %w[finance], name: "Ola")
    @member = make_user(role: "member", name: "Mo")
    c = SkillCandidate.create!(signature: SkillCandidate.signature_for(STEPS), steps: STEPS, domain: "finance", status: "drafted",
                               draft_name: "post-invoice", draft_title: "Post an invoice", draft_description: "d", draft_body: "b")
    @skill = Capture::Publisher.publish!(c, reviewer: @reviewer)
    @schedule = PricingSchedule.current
  end

  # n trips, each taking (steps-1) × spacing, by different people, starting `days_ago`
  def trips(n, spacing:, days_ago:)
    n.times { |i| perform_workflow(@source, "p-#{days_ago}-#{i}", STEPS, start: days_ago.days.ago + i.hours, spacing: spacing) }
  end

  def sweep(now: Time.current)
    Capture::Bounties.sweep(Capture::Congestion.call(now: now), now: now)
  end

  test "default demand schedule: tiers, prices, premiums and validation" do
    assert_equal %w[free slow heavy jammed], @schedule.sorted_tiers.map { |t| t["key"] }
    assert_equal "free", @schedule.tier_for(1.1)["key"]
    assert_equal "heavy", @schedule.tier_for(2.0)["key"]
    assert_equal 40, @schedule.price_for(5).to_i
    assert_equal 15, @schedule.premium_for(2.0).to_i
    bad = @schedule.dup.tap { |s| s.tiers = [{ "key" => "a", "label" => "A", "min_index" => 0, "multiplier" => 2 },
                                              { "key" => "b", "label" => "B", "min_index" => 1, "multiplier" => 1 }]; s.bounty_tier = "a" }
    assert_not bad.valid?
    assert_includes bad.errors[:tiers], "multipliers must not fall as congestion rises"
  end

  test "measures travel time against free-flow and prices congested skills" do
    trips(10, spacing: 5.minutes, days_ago: 40)  # baseline: 10 min
    trips(6, spacing: 15.minutes, days_ago: 3)   # recent: 30 min
    m = Capture::Congestion.call.metrics.find { |x| x.name == "post-invoice" }
    assert_equal 10.0, m.freeflow_minutes
    assert_equal 30.0, m.median_minutes
    assert_equal 3.0, m.congestion_index
    assert_equal "jammed", m.tier
    assert_equal 40, m.price.to_i
    assert_equal 2.0, m.delay_hours # 6 trips × 20 min
    assert_equal 6, m.people
  end

  test "waits between skills count as travel time (handoff bottlenecks)" do
    pre = %w[outlook.receive:invoice outlook.forward:ap]
    Capture::Publisher.publish!(SkillCandidate.create!(signature: "x", steps: pre, domain: "finance", status: "drafted",
      draft_name: "forward-invoice", draft_title: "Forward", draft_description: "d", draft_body: "b"), reviewer: @reviewer)
    6.times do |i|
      t = (i + 1).days.ago
      perform_workflow(@source, "w#{i}", pre, start: t)
      perform_workflow(@source, "w#{i}", STEPS, start: t + 3.hours, spacing: 5.minutes) # waited ~3h for AP
    end
    m = Capture::Congestion.call.metrics.find { |x| x.name == "post-invoice" }
    assert_in_delta 179.0, m.median_wait_minutes, 1
  end

  test "too little traffic is not priced and opens no bounty" do
    trips(3, spacing: 15.minutes, days_ago: 2)
    m = Capture::Congestion.call.metrics.find { |x| x.name == "post-invoice" }
    assert_nil m.tier
    assert_nil m.price
    sweep
    assert_empty Bounty.all
  end

  test "bounty lifecycle: open → accrue → fix → measure → approve → paid credits" do
    trips(10, spacing: 5.minutes, days_ago: 40)
    trips(6, spacing: 15.minutes, days_ago: 3)
    sweep
    bounty = Bounty.sole
    assert_equal "open", bounty.status
    assert_equal 180, bounty.pool.to_i, "6 trips × premium 30"
    assert Notification.exists?(user: @reviewer, kind: "bounty")

    trips(2, spacing: 15.minutes, days_ago: 0.5)
    sweep
    assert_equal 240, bounty.reload.pool.to_i, "new congested trips add their premium"

    # A member proposes a faster way ("Fix this"); a reviewer publishes it as the next version.
    fix = SkillCandidate.create!(signature: "manual:fix", steps: STEPS, origin: "manual", domain: "finance", status: "drafted",
                                 draft_name: "post-invoice", draft_title: "Post an invoice", draft_description: "faster",
                                 draft_body: "new", requested_by: @member)
    Capture::Publisher.publish!(fix, reviewer: @reviewer)
    bounty.reload
    assert_equal ["measuring", @member, "post-invoice", 2], [bounty.status, bounty.solver, bounty.fix_skill_name, bounty.fix_version]
    assert_equal 3.0, bounty.baseline_index

    travel 1.day do
      trips(5, spacing: 6.minutes, days_ago: 0.3) # now 12 min: index 1.2
      sweep
    end
    bounty.reload
    assert_equal "awaiting_approval", bounty.status
    assert_equal 1.2, bounty.result_index
    assert_equal 0.9, bounty.improvement
    assert_equal 216, bounty.payout.to_i

    err = assert_raises(Capture::Bounties::Error) { Capture::Bounties.new.approve!(bounty, by: @member) }
    assert_match(/your own bounty/, err.message)
    err = assert_raises(Capture::Bounties::Error) { Capture::Bounties.new.approve!(bounty, by: make_user(role: "member")) }
    assert_match(/reviewers for this area/, err.message)
    Capture::Bounties.new.approve!(bounty, by: @other_reviewer)
    assert_equal "paid", bounty.reload.status
    assert_equal 216, @member.credits.to_i
    assert Notification.exists?(user: @member, kind: "bounty_paid")
  end

  test "solvers can't approve their own payout; a fix that doesn't help reopens the bounty" do
    trips(10, spacing: 5.minutes, days_ago: 40)
    trips(6, spacing: 15.minutes, days_ago: 3)
    sweep
    Capture::Publisher.revise!(@skill, editor: @reviewer, attrs: { body: "tweak" })
    bounty = Bounty.sole
    assert_equal @reviewer, bounty.solver

    travel 1.day do
      trips(5, spacing: 16.minutes, days_ago: 0.3) # no better
      sweep
    end
    bounty.reload
    assert_equal "open", bounty.status
    assert_match(/didn't reduce congestion/, bounty.notes)
    assert_nil bounty.solver
  end

  test "a faster branch counts as a fix for the parent's bounty" do
    trips(10, spacing: 5.minutes, days_ago: 40)
    trips(6, spacing: 15.minutes, days_ago: 3)
    sweep
    fork = Capture::Publisher.revise!(@skill, editor: @reviewer, attrs: { name: "post-invoice-fast-track" })
    assert_equal ["measuring", "post-invoice-fast-track"], Bounty.sole.values_at(:status, :fix_skill_name)
    assert_equal "post-invoice", fork.parent_skill.name
  end

  test "a bounty closes if congestion clears before anyone fixes it" do
    trips(10, spacing: 5.minutes, days_ago: 40)
    trips(6, spacing: 15.minutes, days_ago: 3)
    sweep
    travel 10.days do
      trips(6, spacing: 5.minutes, days_ago: 1)
      sweep
    end
    assert_equal "closed", Bounty.sole.status
  end

  test "the route planner steers around jammed skills when an equally short road exists" do
    trips(10, spacing: 5.minutes, days_ago: 40)
    trips(6, spacing: 15.minutes, days_ago: 3)
    Capture::Congestion.call
    map = { nodes: [{ id: "start" }, { id: "post-invoice", tier: "jammed" }, { id: "alt", tier: "free" }, { id: "end" }],
            edges: [{ from: "start", to: "post-invoice", kind: "next", traffic: 9 }, { from: "post-invoice", to: "end", kind: "next", traffic: 9 },
                    { from: "start", to: "alt", kind: "next", traffic: 1 }, { from: "alt", to: "end", kind: "next", traffic: 1 }] }
    assert_equal %w[start alt end], Capture::RoutePlanner.new(map).route("start", "end").keys
  end
end
