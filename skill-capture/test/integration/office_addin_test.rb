require "test_helper"

class OfficeAddinTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  setup do
    host! "skills.example.org"
    https!
    @reviewer = make_user(role: "reviewer", domains: ["finance"], name: "Rae Reviewer")
    @member = make_user(role: "member", name: "Mo Member")
  end

  def token_for(user, host: "Excel")
    AddinToken.issue!(user: user, host: host).last
  end

  def api(method, path, user: @member, token: nil, params: nil)
    token ||= token_for(user)
    send(method, path, params: params&.to_json, headers: { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" })
  end

  # ---- manifest & hosting ----

  test "manifest is a valid TaskPaneApp for Excel, Word and PowerPoint served from this origin over HTTPS" do
    get addin_manifest_path
    assert_response :success
    assert_match %r{xml}, response.media_type
    raw = Nokogiri::XML(response.body) { |c| c.strict }
    assert_equal "TaskPaneApp", raw.root.attribute_with_ns("type", "http://www.w3.org/2001/XMLSchema-instance").value
    doc = raw.dup.tap(&:remove_namespaces!)
    assert_equal "OfficeApp", doc.root.name
    assert_match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/, doc.at_xpath("/OfficeApp/Id").text)
    assert_match(/\A\d+\.\d+\.\d+\.\d+\z/, doc.at_xpath("/OfficeApp/Version").text)
    assert_equal %w[Workbook Document Presentation], doc.xpath("/OfficeApp/Hosts/Host").map { |h| h["Name"] }
    assert_equal %w[Workbook Document Presentation], doc.xpath("//VersionOverrides/Hosts/Host").map { |h| h["type"] }
    assert_equal 3, doc.xpath("//Runtime[@lifetime='long']").size
    # every resid points at a defined resource
    defined = doc.xpath("//Resources//*[@id]").map { |n| n["id"] }
    doc.xpath("//*[@resid]").each { |n| assert_includes defined, n["resid"] }

    urls = response.body.scan(/DefaultValue="(https?:[^"]+)"/).flatten + [doc.at_xpath("//AppDomain").text]
    assert urls.any?
    urls.each { |u| assert u.start_with?("https://skills.example.org"), "#{u} must be on this HTTPS origin" }
    response.body.scan(%r{https://skills\.example\.org(/addin/icon-\d+\.png)}).flatten.uniq.each do |path|
      assert File.exist?(Rails.public_path.join(path.delete_prefix("/"))), "missing #{path}"
    end
  end

  test "SKILL_CAPTURE_PUBLIC_URL overrides the origin in the manifest" do
    ENV["SKILL_CAPTURE_PUBLIC_URL"] = "https://capture.contoso.com/"
    get addin_manifest_path
    assert_includes response.body, "<SourceLocation DefaultValue=\"https://capture.contoso.com/addin/taskpane\"/>"
  ensure
    ENV.delete("SKILL_CAPTURE_PUBLIC_URL")
  end

  test "task pane can be framed by Office on the web and loads Office.js first" do
    get addin_taskpane_path
    assert_response :success
    assert_nil response.headers["X-Frame-Options"]
    assert_includes response.headers["Content-Security-Policy"], "https://*.officeapps.live.com"
    assert_operator response.body.index("appsforoffice.microsoft.com/lib/1/hosted/office.js"), :<, response.body.index("importmap")
    assert_includes response.body, %("addin/taskpane")
  end

  test "web console pages are still not frameable" do
    sign_in @member
    get skills_path
    assert_equal "SAMEORIGIN", response.headers["X-Frame-Options"]
  end

  # ---- connecting ----

  test "connect requires sign-in, then issues a personal token handed back to the task pane" do
    get addin_connect_path(host: "Excel", platform: "OfficeOnline")
    assert_redirected_to new_user_session_path

    sign_in @member
    get addin_connect_path(host: "Excel", platform: "OfficeOnline")
    assert_response :success
    assert_includes response.body, "Connect Office to Skill Capture"

    post addin_connect_path, params: { host: "Excel", platform: "OfficeOnline" }
    assert_equal "no-store", response.headers["Cache-Control"]
    token = response.body[/data-token="(sca_[^"]+)"/, 1]
    assert token
    record = AddinToken.sole
    assert_equal [@member, "Excel", "OfficeOnline"], [record.user, record.host, record.platform]
    refute_equal token, record.token_digest

    sign_out @member
    api(:get, api_v1_addin_me_path, token: token)
    assert_equal "Mo Member", response.parsed_body["name"]
  end

  test "tokens stop working when revoked or when the person is deactivated" do
    token = token_for(@member)
    api(:delete, api_v1_addin_me_path, token: token)
    assert_response :no_content
    api(:get, api_v1_addin_me_path, token: token)
    assert_response :unauthorized

    token2 = token_for(@member)
    @member.update!(active: false)
    api(:get, api_v1_addin_me_path, token: token2)
    assert_response :unauthorized
  end

  test "people can see and disconnect their Office apps from the console" do
    AddinToken.issue!(user: @member, host: "Word", platform: "PC")
    sign_in @member
    get connected_apps_path
    assert_includes response.body, "Word on PC"
    delete connected_app_path(AddinToken.sole)
    assert AddinToken.sole.revoked_at
  end

  test "add-in tokens can't be used on the integration API and vice versa" do
    api(:post, api_v1_events_path, params: { events: [] })
    assert_response :unauthorized
    _, source_token = make_source
    api(:get, api_v1_addin_me_path, token: source_token)
    assert_response :unauthorized
  end

  # ---- capture ----

  test "events from the add-in are attributed to the connected person, whatever the payload says" do
    api(:post, api_v1_addin_events_path, params: { host: "Excel", events: [
      { action: "excel.data.sorted", label: "Sort data", session: "s1", occurred_at: 1.minute.ago.utc.iso8601,
        actor: { id: "someone-else", name: "Spoof" }, context: { app: "excel", sheet: "Salaries" } }
    ] })
    assert_response :accepted
    assert_equal 1, response.parsed_body["dropped_fields"]
    e = UsageEvent.sole
    assert_equal [@member.actor_key, "Mo Member"], [e.actor_key, e.actor_name]
    assert_equal ["excel", "Skill Capture for Excel"], [e.source.kind, e.source.name]
    assert_equal({ "app" => "excel" }, e.context)
  end

  test "unknown Office hosts are refused" do
    api(:post, api_v1_addin_events_path, params: { host: "Visio", events: [] })
    assert_response :unprocessable_entity
  end

  test "repeated add-in workflows are detected and contributors are notified on publish" do
    steps = %w[excel.document.opened excel.rows.inserted excel.formula.changed excel.data.sorted]
    [@member, @reviewer, @member].each_with_index do |u, i|
      api(:post, api_v1_addin_events_path, user: u, params: { host: "Excel", events: steps.each_with_index.map { |k, j|
        { action: k, label: k.humanize, domain: "finance", session: "s#{i}", occurred_at: ((i + 1).days.ago + j.minutes).utc.iso8601 } } })
    end
    perform_enqueued_jobs { CaptureSweepJob.perform_now }
    c = SkillCandidate.sole
    assert_equal ["Mo Member", "Rae Reviewer"], c.contributor_names.sort

    api(:post, approve_api_v1_addin_candidate_path(c), user: @reviewer)
    assert_response :created
    assert Notification.exists?(user: @member, kind: "skill_published")
  end

  # ---- record a procedure ----

  test "a recorded procedure becomes a drafted candidate for that area, keeping its author's title" do
    perform_enqueued_jobs do
      api(:post, api_v1_addin_procedures_path, params: {
        host: "Excel", title: "Reconcile the bank statement", domain: "Finance", description: "Monthly, after the statement arrives.",
        steps: [{ action: "excel.data.sorted", label: "Sort data" },
                { action: "excel.step:check-totals", label: "Check totals match the bank statement" },
                { action: "bad action!", label: "dropped" }]
      })
    end
    assert_response :created
    c = SkillCandidate.sole
    assert_equal %w[excel.data.sorted excel.step:check-totals], c.steps
    assert_equal ["finance", "manual", @member], [c.domain, c.origin, c.requested_by]
    assert_equal ["drafted", "Reconcile the bank statement", "reconcile-the-bank-statement"], [c.status, c.draft_title, c.draft_name]
    assert_equal "Monthly, after the statement arrives.", c.draft_description
    assert_includes c.draft_body, "Check totals match the bank statement"
    assert Notification.exists?(user: @reviewer, subject: c)
  end

  test "a procedure needs a title and steps" do
    api(:post, api_v1_addin_procedures_path, params: { host: "Word", title: "", steps: [] })
    assert_response :unprocessable_entity
  end

  # ---- library & review in the pane ----

  test "library search and skill detail" do
    skill = Capture::Publisher.publish!(drafted_candidate, reviewer: @reviewer)
    api(:get, api_v1_addin_skills_path(q: "bill"))
    assert_equal [skill.name], response.parsed_body.map { |s| s["name"] }
    api(:get, api_v1_addin_skill_path(skill.name))
    assert_includes response.parsed_body["body"], "Create the order"
    assert_equal "https://skills.example.org/skills/#{skill.id}", response.parsed_body["url"]
  end

  test "reviewers review in the pane; members can't" do
    c = drafted_candidate
    api(:get, api_v1_addin_candidates_path, user: @reviewer)
    assert_equal [c.id], response.parsed_body.map { |x| x["id"] }
    api(:get, api_v1_addin_candidates_path, user: @member)
    assert_empty response.parsed_body

    api(:post, approve_api_v1_addin_candidate_path(c), user: @member)
    assert_response :forbidden
    api(:post, reject_api_v1_addin_candidate_path(c), user: @reviewer, params: { notes: "Too specific" })
    assert_response :no_content
    assert_equal ["rejected", "Too specific"], c.reload.values_at(:status, :review_notes)
  end
end
