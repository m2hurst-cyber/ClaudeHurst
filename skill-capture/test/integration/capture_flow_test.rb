require "test_helper"

# End to end (Definition of Done): a collector reports a repeated task → the sweep
# proposes and drafts a skill → the area's reviewer publishes it → people and
# agents can find it.
class CaptureFlowTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  STEPS = [["excel.open:close_wb", "Open the month-end close workbook"],
           ["excel.run_macro:reconcile", "Run the reconciliation macro"],
           ["outlook.send:summary", "Email the close summary to the controller"]].freeze

  setup do
    @source, @token = make_source(name: "Finance Excel add-in")
    @reviewer = make_user(role: "reviewer", domains: ["finance"], name: "Rae Reviewer")
    @member = make_user(role: "member", name: "Mo Member")
  end

  def auth = { "Authorization" => "Bearer #{@token}" }

  def post_events(events, headers: auth)
    post api_v1_events_path, params: { events: events }.to_json, headers: headers.merge("Content-Type" => "application/json")
  end

  test "the ingest API requires an active source token" do
    post_events([], headers: {})
    assert_response :unauthorized
    @source.update!(active: false)
    post_events([], headers: auth)
    assert_response :unauthorized
  end

  test "report → detect → draft → review → publish → discoverable" do
    events = 3.times.flat_map do |i|
      STEPS.each_with_index.map do |(key, label), j|
        { action: key, label: label, domain: "finance", actor: { id: "emp-#{i}", name: "Employee #{i}" },
          session: "sess-#{i}", occurred_at: ((i + 1).days.ago + j.minutes).utc.iso8601,
          context: { app: "excel", comment: "do not store me" } }
      end
    end
    post_events(events)
    assert_response :accepted
    assert_equal({ "accepted" => 9, "rejected" => [], "dropped_fields" => 9 }, response.parsed_body)

    perform_enqueued_jobs { CaptureSweepJob.perform_now }
    candidate = SkillCandidate.sole
    assert_equal ["drafted", "template", "finance"], [candidate.status, candidate.draft_generator, candidate.domain]

    # A member can't see or approve someone else's review item.
    sign_in @member
    get skill_candidate_path(candidate)
    assert_redirected_to root_path
    post approve_skill_candidate_path(candidate)
    assert_equal "drafted", candidate.reload.status
    sign_out @member

    sign_in @reviewer
    get skill_candidates_path
    assert_includes response.body, "Open the month-end close workbook"
    get skill_candidate_path(candidate)
    assert_response :success
    patch skill_candidate_path(candidate), params: { skill_candidate: { draft_name: "month-end-close", draft_tags: "close, Month End" } }
    assert_equal %w[close month-end], candidate.reload.draft_tags
    post approve_skill_candidate_path(candidate)
    skill = Skill.find_by!(name: "month-end-close")
    assert_redirected_to skill_path(skill)
    assert_equal ["Finance Excel add-in"], skill.source["sources"]
    sign_out @reviewer

    sign_in @member
    get skills_path(q: "month-end")
    assert_includes response.body, skill.title
    get download_skill_path(skill)
    assert_match(/\A---\nname: month-end-close\n/, response.body)
    get edit_skill_path(skill)
    assert_redirected_to root_path

    get api_v1_skills_path, headers: auth
    assert_equal ["month-end-close"], response.parsed_body.map { |s| s["name"] }
    get api_v1_skill_path("month-end-close"), headers: auth
    assert_includes response.parsed_body["skill_md"], "name: month-end-close"
  end

  test "anyone can request a skill; it routes to that area's reviewers" do
    sign_in @member
    post skill_candidates_path, params: { skill_candidate: { draft_title: "Handle a disputed invoice", domain: "Finance",
                                                             draft_description: "When a customer disputes a charge.", draft_body: "1. Pull the invoice" } }
    c = SkillCandidate.sole
    assert_redirected_to skill_candidate_path(c)
    assert_equal ["finance", "drafted", "handle-a-disputed-invoice", @member], [c.domain, c.status, c.draft_name, c.requested_by]
    assert Notification.exists?(user: @reviewer, subject: c)
    get skill_candidate_path(c)
    assert_response :success, "requesters can follow their own request"
  end

  test "admins manage people and sources; tokens are shown once and stored hashed" do
    admin = make_user(role: "admin")
    sign_in @member
    get admin_sources_path
    assert_redirected_to root_path
    sign_out @member

    sign_in admin
    post admin_sources_path, params: { source: { name: "Month-end flow", kind: "integration" } }
    token = response.body[/sc_[A-Za-z0-9_\-]+/]
    assert token
    assert_equal Source.digest(token), Source.find_by!(name: "Month-end flow").token_digest
    refute Source.where(token_digest: token).exists?

    post admin_users_path, params: { user: { name: "New Person", email: "new@example.test", role: "reviewer", domains: "Support, ops" } }
    assert_match(/One-time password: \S+/, flash[:notice])
    assert_equal %w[support ops], User.find_by!(email: "new@example.test").domains
  end

  test "no accounts exist until someone creates one" do
    User.delete_all
    get root_path
    assert_redirected_to new_user_session_path
    post user_session_path, params: { user: { email: "admin@example.test", password: "password123" } }
    assert_response :unprocessable_entity
  end
end
