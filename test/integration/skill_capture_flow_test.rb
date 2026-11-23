require "test_helper"

# End-to-end (spec §11): people repeat a task in the app → the sweep proposes a
# skill → a process owner publishes it → everyone (and agents, via JSON) can find it.
class SkillCaptureFlowTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  setup do
    ENV["SKILL_CAPTURE_LLM"] = "off"
    @ops = make_user(role: "ops", first_name: "Omar")
    @sales = make_user(role: "sales", first_name: "Sally")
  end

  teardown { ENV.delete("SKILL_CAPTURE_LLM") }

  test "collector records structure only, never submitted values" do
    sign_in @sales
    post reminders_path, params: { reminder: { remind_at: 1.hour.from_now, channel: "email", recurrence: "none",
                                               message: "Call Jane at 555-0100 about the overdue invoice" } }
    e = UsageEvent.last
    assert_equal "reminders#create", e.workflow_key
    assert_equal @sales, e.user
    assert_equal({ "channel" => "email", "recurrence" => "none" }, e.context)
    refute_includes e.attributes.to_json, "555-0100"
    refute_includes e.attributes.to_json, "Jane"
  end

  test "reads, failed submissions and the review UI itself are not captured" do
    sign_in @sales
    get reminders_path
    post reminders_path, params: { reminder: { remind_at: nil, channel: "nope", message: "" } }
    post skill_candidates_path, params: { skill_candidate: { draft_title: "Thing", domain: "sales" } }
    assert_equal 0, UsageEvent.count
  end

  test "repeat → detect → draft → publish → discoverable" do
    sign_in @ops
    3.times do
      # The same three-step workflow, through the real controllers' tracking hook.
      post tasks_path, params: { task: { title: "Check the filler line", due_on: Date.tomorrow, priority: "normal" } }
      post reminders_path, params: { reminder: { remind_at: 1.hour.from_now, channel: "email", recurrence: "none", message: "x" } }
      travel 2.hours # new work session
    end
    assert_equal %w[tasks#create reminders#create], UsageEvent.order(:id).first(2).map(&:workflow_key)

    perform_enqueued_jobs { SkillCaptureSweepJob.perform_now }
    candidate = SkillCandidate.find_by!(signature: "tasks#create>reminders#create")
    assert_equal "drafted", candidate.status
    assert_equal "template", candidate.draft_generator

    # Sales owns tasks/reminders, so sales reviews; ops (the doer) can see but not approve.
    get skill_candidate_path(candidate)
    assert_response :success
    post approve_skill_candidate_path(candidate)
    assert_equal "drafted", candidate.reload.status

    sign_out @ops
    sign_in @sales
    get skill_candidates_path
    assert_response :success
    assert_includes response.body, candidate.display_title

    patch skill_candidate_path(candidate), params: { skill_candidate: { draft_name: "schedule-follow-up", draft_tags: "follow-up, sales" } }
    post approve_skill_candidate_path(candidate)
    skill = Skill.find_by!(name: "schedule-follow-up")
    assert_redirected_to skill_path(skill)
    assert_equal @sales, skill.published_by
    assert_equal [@ops.display_name], skill.source["contributors"]

    sign_out @sales
    sign_in @ops
    get skills_path(format: :json, q: "follow-up")
    assert_equal ["schedule-follow-up"], response.parsed_body.map { |s| s["name"] }
    get download_skill_path(skill)
    assert_match(/\A---\nname: schedule-follow-up\n/, response.body)
    get skill_path(skill)
    assert_response :success
  end

  test "anyone can request a skill manually; it routes to the right reviewers" do
    sign_in @sales
    post skill_candidates_path(format: :json), params: { skill_candidate: {
      draft_title: "Handle a short-shipped order", domain: "ops", draft_description: "What to do when a run under-delivers.",
      draft_body: "1. Check the FG lot\n2. Call the customer", steps: ["production_runs#complete", "bogus#thing"] } }
    assert_response :created
    c = SkillCandidate.find(response.parsed_body["id"])
    assert_equal %w[production_runs#complete], c.steps
    assert_equal "drafted", c.status
    assert_equal "handle-a-short-shipped-order", c.draft_name
    assert Notification.exists?(user: @ops, subject: c)
  end
end
