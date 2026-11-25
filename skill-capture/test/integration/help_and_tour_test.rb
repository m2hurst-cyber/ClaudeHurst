require "test_helper"

class HelpAndTourTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup { @user = make_user(domains: %w[finance]) }

  # ---------- the walkthrough ----------

  test "a brand new person lands on the walkthrough, and only the first time" do
    post user_session_path, params: { user: { email: @user.email, password: @user.password } }
    assert_redirected_to tour_path

    get tour_path
    assert_response :success
    assert_select "h1", "Getting started"
    delete destroy_user_session_path

    # Having seen it once, they go wherever they were going.
    post user_session_path, params: { user: { email: @user.email, password: @user.password } }
    assert_redirected_to root_path
  end

  test "steps tick themselves off when the work is actually done" do
    sign_in @user
    tour = Capture::Onboarding.for(@user)
    capture_step = tour.steps.find { |s| s.key == "capture" }
    refute capture_step.done?

    WorksheetCapture.create!(user: @user, sheet_name: "DCF", address: "A1:H40", provider: "excel")
    assert Capture::Onboarding.for(@user.reload).steps.find { |s| s.key == "capture" }.done?
  end

  test "people only get the steps that are theirs" do
    member = Capture::Onboarding.for(@user).steps.map(&:key)
    refute_includes member, "review"
    refute_includes member, "tune"

    reviewer = Capture::Onboarding.for(make_user(role: "reviewer", domains: %w[finance])).steps.map(&:key)
    assert_includes reviewer, "review"
    refute_includes reviewer, "tune"

    assert_includes Capture::Onboarding.for(make_user(role: "admin")).steps.map(&:key), "tune"
  end

  test "the nudge shows until it is finished or waved away, and never on the tour itself" do
    sign_in @user
    get skills_path
    assert_select "a[href=?]", tour_path, text: "Show me"

    get tour_path
    assert_select "a", text: "Show me", count: 0

    post dismiss_tour_path
    assert_redirected_to root_path
    get skills_path
    assert_select "a", text: "Show me", count: 0
    assert @user.reload.tour_dismissed_at.present?
  end

  test "a dismissed tour can be picked up again" do
    @user.update!(tour_dismissed_at: Time.current)
    sign_in @user
    post restart_tour_path
    assert_redirected_to tour_path
    assert_nil @user.reload.tour_dismissed_at
  end

  test "progress counts only what has been done" do
    sign_in @user
    tour = Capture::Onboarding.for(@user)
    assert_equal 0, tour.done_count
    assert_equal 0, tour.percent

    get tour_path # looking around is itself the first step
    after = Capture::Onboarding.for(@user.reload)
    assert_equal 1, after.done_count
    assert_operator after.percent, :>, 0
    refute after.complete?
  end

  # ---------- the help centre ----------

  test "every guide file parses and carries what the pages need" do
    guides = Capture::Help.guides
    assert_operator guides.size, :>=, 9
    guides.each do |g|
      assert g.title.present?, "#{g.slug} has no title"
      assert g.summary.present?, "#{g.slug} has no summary"
      assert g.body.length > 200, "#{g.slug} is too thin to be useful"
      assert_includes Capture::Help::SECTIONS.keys, g.section, "#{g.slug} is in an unknown section"
    end
  end

  test "every FAQ answer is real, and every guide it points at exists" do
    questions = Capture::Help.faq
    assert_operator questions.size, :>=, 20
    slugs = Capture::Help.guides.map(&:slug)
    questions.each do |q|
      assert q.question.to_s.end_with?("?"), "not a question: #{q.question}"
      assert q.answer.to_s.length > 40, "answer too thin: #{q.question}"
      assert_includes slugs, q.guide, "#{q.question} points at a missing guide" if q.guide
    end
  end

  test "the help index lists the guides and the questions" do
    sign_in @user
    get help_path
    assert_response :success
    assert_select "h1", "Help"
    assert_select "a[href=?]", help_guide_path("getting-started")
    assert_select "details summary", /granularity|prompt|skill/i
  end

  test "search finds a guide by its subject and a question by its words" do
    sign_in @user
    get help_path, params: { q: "granularity" }
    assert_response :success
    assert_select "a[href=?]", help_guide_path("granularity")

    assert Capture::Help.search("too many prompts").any? { |h| h.kind == "question" }
    assert_empty Capture::Help.search("x"), "a single character is not a search"
  end

  test "a guide page renders its body and what relates to it" do
    sign_in @user
    get help_guide_path("send-a-skill")
    assert_response :success
    assert_select "h1", "Send a skill to someone"
    assert_select "article", /escrow/i
  end

  test "a missing guide says so instead of failing" do
    sign_in @user
    get help_guide_path("no-such-thing")
    assert_redirected_to help_path
  end

  test "agents can read the help as markdown" do
    sign_in @user
    get help_guide_path("connect-an-agent", format: :md)
    assert_response :success
    assert_equal "text/markdown; charset=utf-8", response.media_type + "; charset=utf-8"
    assert_match(/^# Connect an agent/, response.body)

    get help_path(format: :md)
    assert_match(/^# Skill Capture help/, response.body)
    assert_match(/Frequently asked/, response.body)
  end

  test "help needs a sign-in like everything else" do
    get help_path
    assert_redirected_to new_user_session_path
  end

  test "markdown links are allowed to our own pages but not to anything that can run" do
    html = ApplicationController.helpers.skill_markdown("[map](/map) [evil](javascript:alert(1))")
    assert_includes html, '<a href="/map"'
    refute_includes html, "javascript:"
  end
end
