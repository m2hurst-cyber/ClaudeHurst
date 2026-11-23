require "test_helper"

# Simulation tests: script known workflows into the event stream and check the
# detector proposes exactly those (spec §8; Definition of Done: >80% captured).
class WorkflowDetectorTest < ActiveSupport::TestCase
  SCRIPTED = {
    month_end_close: %w[excel.open:close_wb excel.refresh:gl excel.run_macro:reconcile outlook.send:summary],
    escalation: %w[zendesk.view:ticket slack.post:incident jira.create:bug zendesk.reply:update],
    release_notes: %w[github.list:merged_prs docs.edit:release_notes slack.post:announcements],
    new_vendor: %w[sharepoint.upload:w9 erp.create:vendor email.send:vendor_welcome],
    weekly_kpis: %w[bi.refresh:kpi_dashboard pptx.update:kpi_slides]
  }.freeze

  setup do
    @source, = make_source
  end

  test "captures every scripted workflow with no fragments or noise" do
    SCRIPTED.values.each_with_index do |steps, wi|
      3.times { |rep| perform_workflow(@source, "actor-#{(wi + rep) % 3}", steps, start: (10 - rep).days.ago + wi.hours) }
    end
    perform_workflow(@source, "actor-0", %w[mail.read:inbox calendar.accept:invite], start: 2.days.ago)
    2.times { |i| perform_workflow(@source, "actor-1", %w[crm.open:lead crm.update:lead crm.log:call], start: (3 + i).days.ago) }

    found = Capture::WorkflowDetector.new.detect.map(&:steps)
    captured = SCRIPTED.values.count { |s| found.include?(s) }

    assert_operator captured.to_f / SCRIPTED.size, :>=, 0.8
    assert_equal SCRIPTED.values.sort, found.sort, "expected exactly the scripted workflows"
  end

  test "workflows longer than the step window come back as one workflow" do
    long = %w[a.one b.two c.three d.four e.five f.six g.seven h.eight i.nine]
    3.times { |i| perform_workflow(@source, "actor-#{i}", long, start: (i + 1).days.ago) }
    assert_equal [long], Capture::WorkflowDetector.new(max_steps: 6).detect.map(&:steps)
  end

  test "idle gaps split sessions" do
    3.times do |i|
      start = (i + 1).days.ago
      perform_workflow(@source, "a", %w[erp.create:invoice email.send:invoice], start: start, session: "s")
      perform_workflow(@source, "a", %w[bank.record:payment], start: start + 2.hours, session: "s")
    end
    found = Capture::WorkflowDetector.new.detect.map(&:steps)
    assert_equal [%w[erp.create:invoice email.send:invoice]], found
  end

  test "consecutive duplicates collapse and repeats in one session count" do
    3.times do |i|
      perform_workflow(@source, "a", %w[erp.receive:lot erp.receive:lot erp.release:run], start: 1.day.ago + (i * 10).minutes, session: "s")
    end
    p = Capture::WorkflowDetector.new.detect.first
    assert_equal %w[erp.receive:lot erp.release:run], p.steps
    assert_equal 3, p.occurrences
  end

  test "distinct-people threshold" do
    3.times { |i| perform_workflow(@source, "a", %w[x.one y.two], start: (i + 1).days.ago) }
    assert_empty Capture::WorkflowDetector.new(min_actors: 2).detect
    assert_equal 1, Capture::WorkflowDetector.new(min_actors: 1).detect.size
  end

  test "call creates a candidate, routes it to the area's reviewers and updates on rerun" do
    finance = make_user(role: "reviewer", domains: ["finance"])
    support = make_user(role: "reviewer", domains: ["support"])
    admin = make_user(role: "admin")
    3.times { |i| perform_workflow(@source, "a-#{i}", SCRIPTED[:month_end_close], start: (i + 1).days.ago, domain: "finance") }

    result = Capture::WorkflowDetector.call
    c = result.created.sole
    assert_equal "finance", c.domain
    assert_equal 3, c.distinct_actor_count
    assert_equal ["Person a-0", "Person a-1", "Person a-2"], c.contributor_names
    assert Notification.exists?(user: finance, subject: c)
    assert Notification.exists?(user: admin, subject: c)
    assert_not Notification.exists?(user: support, subject: c)
    assert AuditLog.exists?(action: "skill_candidate.detected", subject: c)

    perform_workflow(@source, "a-0", SCRIPTED[:month_end_close], start: 1.hour.ago, domain: "finance")
    assert_empty Capture::WorkflowDetector.call.created
    assert_equal 4, c.reload.occurrence_count
  end

  test "area falls back to action definitions when events carry none" do
    ActionDefinition.create!(key: "x.one", label: "One", domain: "ops")
    3.times { |i| perform_workflow(@source, "a", %w[x.one y.two], start: (i + 1).days.ago) }
    assert_equal "ops", Capture::WorkflowDetector.call.created.sole.domain
  end

  test "fragments of a reviewed workflow are not re-proposed" do
    full = SCRIPTED[:new_vendor]
    SkillCandidate.create!(signature: SkillCandidate.signature_for(full), steps: full, status: "rejected")
    3.times { |i| perform_workflow(@source, "a", full.first(2), start: (i + 1).days.ago) }
    assert_empty Capture::WorkflowDetector.call.created
  end
end
