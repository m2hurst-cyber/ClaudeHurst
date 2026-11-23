require "test_helper"

# Simulation tests (spec §8): script known workflows into the event stream and
# check the detector proposes exactly those workflows.
class SkillCapture::WorkflowDetectorTest < ActiveSupport::TestCase
  SCRIPTED = {
    run_production: %w[production_runs#create production_runs#release production_runs#start_run production_runs#complete production_runs#create_invoice],
    quote_to_contract: %w[quotes#create quotes#send_out quotes#mark_accepted contracts#create contract_pricing_tiers#create],
    bill_and_collect: %w[invoices#create invoices#send_out payments#create],
    receive_materials: %w[raw_materials#create raw_material_lots#create],
    onboard_customer: %w[companies#create contacts#create deals#create activities#create]
  }.freeze

  setup do
    @users = 3.times.map { |i| make_user(role: %w[ops sales finance][i]) }
  end

  test "captures every scripted repeated workflow (>= 80% coverage required)" do
    SCRIPTED.values.each_with_index do |steps, wi|
      3.times do |rep|
        # Different people, separate sessions, interleaved over several days.
        perform_workflow(@users[(wi + rep) % 3], steps, start: (10 - rep).days.ago + wi.hours)
      end
    end
    # Noise: one-off actions and a workflow done only twice.
    perform_workflow(@users[0], %w[tasks#create reminders#create], start: 2.days.ago)
    perform_workflow(@users[1], %w[boms#create boms#update products#create], start: 3.days.ago)
    perform_workflow(@users[1], %w[boms#create boms#update products#create], start: 4.days.ago)

    found = SkillCapture::WorkflowDetector.new.detect.map(&:steps)
    captured = SCRIPTED.values.count { |s| found.include?(s) }

    assert_operator captured.to_f / SCRIPTED.size, :>=, 0.8, "captured only #{captured}/#{SCRIPTED.size}: #{found.inspect}"
    assert_equal SCRIPTED.size, captured
    # Precision: nothing besides the scripted workflows (no fragments, no noise).
    assert_equal SCRIPTED.values.sort, found.sort
  end

  test "splits sessions on idle gaps so unrelated actions don't chain" do
    3.times do |i|
      start = (i + 1).days.ago
      perform_workflow(@users[0], %w[invoices#create invoices#send_out], start: start)
      perform_workflow(@users[0], %w[payments#create], start: start + 2.hours, session: "same") # long gap
    end
    found = SkillCapture::WorkflowDetector.new.detect.map(&:steps)
    assert_includes found, %w[invoices#create invoices#send_out]
    assert_not found.any? { |s| s.include?("payments#create") }
  end

  test "collapses consecutive duplicates and counts repetition within one session" do
    start = 1.day.ago
    3.times do |i|
      perform_workflow(@users[0], %w[raw_material_lots#create raw_material_lots#create raw_material_lots#create production_runs#release],
                       start: start + (i * 10).minutes, session: "s1")
    end
    p = SkillCapture::WorkflowDetector.new.detect.find { |x| x.steps == %w[raw_material_lots#create production_runs#release] }
    assert p, "expected the collapsed workflow to be detected"
    assert_equal 3, p.occurrences
  end

  test "respects the distinct-people threshold" do
    3.times { |i| perform_workflow(@users[0], %w[quotes#create quotes#send_out], start: (i + 1).days.ago) }
    assert_empty SkillCapture::WorkflowDetector.new(min_users: 2).detect
    assert_equal 1, SkillCapture::WorkflowDetector.new(min_users: 1).detect.size
  end

  test "call upserts candidates, notifies domain reviewers and audits; reruns update counts" do
    reviewer = @users[0] # ops
    3.times { |i| perform_workflow(@users[i], SCRIPTED[:run_production], start: (i + 1).days.ago) }

    result = SkillCapture::WorkflowDetector.call
    assert_equal 1, result.created.size
    c = result.created.first
    assert_equal "ops", c.domain
    assert_equal 3, c.occurrence_count
    assert_equal 3, c.distinct_user_count
    assert_equal @users.map(&:id).sort, c.contributor_ids
    assert Notification.exists?(user: reviewer, subject: c, kind: "skill_candidate")
    assert_not Notification.exists?(user: @users[1], subject: c), "sales users don't review ops workflows"
    assert AuditLog.exists?(action: "skill_candidate.detected", subject: c)

    perform_workflow(@users[0], SCRIPTED[:run_production], start: 1.hour.ago)
    again = SkillCapture::WorkflowDetector.call
    assert_empty again.created
    assert_equal 4, c.reload.occurrence_count
  end

  test "does not re-propose a fragment of an already reviewed workflow" do
    full = SCRIPTED[:bill_and_collect]
    SkillCandidate.create!(signature: SkillCandidate.signature_for(full), steps: full, status: "rejected", domain: "finance")
    3.times { |i| perform_workflow(@users[2], full.first(2), start: (i + 1).days.ago) }
    result = SkillCapture::WorkflowDetector.call
    assert_empty result.created
  end
end
