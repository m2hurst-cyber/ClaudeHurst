require "test_helper"

# The top bar: five buckets by function, each a menu. Counts that need a decision from you roll up to
# the bucket; a backlog to work through (screened macros) shows inside the menu but doesn't shout.
class NavigationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    Capture::Taxonomy.ensure_defaults!
    @admin = make_user(role: "admin", name: "Ada Admin")
    @member = make_user(role: "member", domains: %w[finance], name: "Mel Member")
  end

  test "a member sees four buckets, admin pages only for admins, and every link is in a menu" do
    sign_in @member
    get skills_path
    buttons = css_select("nav[aria-label=Sections] [data-nav-menu-target=button]").map { |b| b.text.squish.split.first }
    assert_equal %w[Library Work Review Market], buttons
    assert_select "nav[aria-label=Sections] a[href=?]", skill_map_path
    assert_select "nav[aria-label=Sections] a[href=?]", flows_path
    assert_select "nav[aria-label=Sections] a[href=?]", admin_users_path, count: 0

    # every menu item carries a one-line note, so the bucket is readable without clicking through
    notes = css_select("nav[aria-label=Sections] a span.text-xs").map { |s| s.text.squish }
    assert_operator notes.size, :>=, 10
    assert_includes notes, "How the skills connect: roads, junctions, handoffs"

    sign_in @admin
    get skills_path
    assert_equal %w[Library Work Review Market Admin], css_select("nav[aria-label=Sections] [data-nav-menu-target=button]").map { |b| b.text.squish.split.first }
    assert_select "nav[aria-label=Sections] a[href=?]", admin_audit_logs_path
  end

  test "the bucket badge counts what waits on you, not the backlog behind it" do
    steps = %w[x.a:1 x.b:2]
    SkillCandidate.create!(signature: SkillCandidate.signature_for(steps), steps: steps, domain: "finance", status: "drafted",
                           draft_name: "waiting-one", draft_title: "Waiting one", draft_description: "d", draft_body: "1. a")
    3.times { |i| MacroReview.create!(subject_kind: "skill", subject_key: "s#{i}", title: "Screened #{i}", verdict: "macro", score: 6) }
    sign_in @admin
    get skills_path
    review = css_select("nav[aria-label=Sections] [data-nav-menu-target=button]").find { |b| b.text.include?("Review") }
    assert_equal "1", review.css("span").first&.text, "one skill waiting; the three screened macros stay quiet"
    assert_select "nav[aria-label=Sections] a[href=?] span", macro_reviews_path, text: "3"
  end

  test "the menu opens, closes and is reachable by keyboard" do
    sign_in @admin
    get skills_path
    assert_select "[data-controller=nav-menu][data-action=?]", "nav-menu:close->nav-menu#close", minimum: 4
    assert_select "[data-nav-menu-target=button][aria-expanded=false][aria-haspopup=menu]", minimum: 4
    assert_select "[data-nav-menu-target=panel][hidden][role=menu]", minimum: 4
    assert_select "[data-nav-menu-target=button][data-action*=?]", "keydown->nav-menu#nav", minimum: 4
  end
end
