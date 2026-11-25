require "test_helper"

# The front door: one question answered across everything, the road around the best answer, and the
# work waiting on you when there's no question.
class FrontDoorTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    Capture::Taxonomy.ensure_defaults!
    Capture::Models.ensure_defaults!
    @admin = make_user(role: "admin", name: "Ada Admin")
    @pm = make_user(role: "member", domains: %w[field-services jobcost], name: "Jordan Pike")
    Capture::Playbook.find("roofing-solar").install!(user: @admin)
    Capture::Playbook.find("jobcost-worksheets").install!(user: @admin)
  end

  test "a question in a sentence finds the step that answers it" do
    sign_in @pm
    r = Capture::Find.call("what do I do when the tear-off finds rot", viewer: @pm)
    assert_equal "price-the-hidden-damage", r[:best].key, "the instructions are searched, not just titles"
    refute r[:loose]
  end

  test "one question searches skills, playbooks, formulas and templates at once" do
    sign_in @pm
    get find_path(q: "retainage")
    assert_response :success
    r = Capture::Find.call("retainage", viewer: @pm)
    assert_operator r[:total], :>, 2
    assert_includes r[:groups].keys, "skills"
    assert_includes r[:groups].keys, "formulas"
    assert_select "section[aria-label='Best answer']"
    assert_select "h1", text: /answers for “retainage”/
    best = r[:best]
    assert_select "a", text: best.title, count: 1, message: "the best answer isn't repeated in its own group"

    # the formula library answers a one-word question
    formulas = r[:groups]["formulas"].map(&:key)
    assert_includes formulas, "retainage"
  end

  test "a verb puts the action first: 'start a roofing job' offers to start one" do
    sign_in @pm
    get find_path(q: "start a roofing and solar job")
    r = Capture::Find.call("start a roofing and solar job", viewer: @pm)
    assert_equal "start", r[:intent]
    assert_equal "playbooks", r[:best].group
    assert_equal "Start a job", r[:best].action
    assert_select "a", text: "Start a job"
  end

  test "the best answer comes with the stretch of road it sits on" do
    sign_in @pm
    get find_path(q: "bill the job")
    best = Capture::Find.call("bill the job", viewer: @pm)[:best]
    assert_equal "bill-the-roofing-job", best.key
    map = Capture::Find.neighbourhood(best.key, @pm)
    assert_includes map[:before].map { |n| n[:name] }, "inspect-and-sign-off-the-roof"
    assert_includes map[:after].map { |n| n[:name] }, "close-out-the-roofing-job"
    assert_select "section[aria-label='Best answer'] a", text: "Inspect, correct and sign off"
    # clicking a neighbour re-centres the map without losing the question
    get find_path(q: "bill the job", centre: "close-out-the-roofing-job")
    assert_select "section[aria-label='Best answer'] span", text: "Close out the job and register the warranty"
  end

  test "a job in flight is findable by its reference, and only by the people on it" do
    run = @pm.playbook_runs.create!(playbook_key: "roofing-solar", reference: "J-7788")
    Capture::Legs.new(run).verify_all!
    sign_in @pm
    get find_path(q: "J-7788")
    assert_equal "jobs", Capture::Find.call("J-7788", viewer: @pm)[:best].group
    assert_select "a", text: "Job J-7788"
    nosy = make_user(role: "member", name: "Nosy Parker")
    assert_equal 0, Capture::Find.call("J-7788", viewer: nosy)[:total]
    sign_in nosy
    get find_path(q: "J-7788")
    assert_select "p", text: /Nothing matched/
  end

  test "with no question, the desk shows what is waiting on you" do
    run = @pm.playbook_runs.create!(playbook_key: "roofing-solar", reference: "J-5000")
    Capture::Legs.new(run).verify_all!
    flow = Flow.create!(user: @pm, name: "Bid", steps: Flow.normalize_steps([{ title: "Take off the roof", app: "Excel", assignee: "me" }]))
    FlowRun.start!(flow, user: @pm)
    sign_in @pm
    get root_path
    assert_response :success
    assert_select "h1", text: /What are you trying to do/
    assert_select "section[aria-label='Your desk'] h3", text: "Your turn in a flow"
    assert_select "a", text: "Take off the roof"
    assert_select "a", text: "Job J-5000"
    assert_select "span", text: /Next: Qualify the lead and book the survey · waiting on/, count: 1,
                  message: "the next leg is the first one along the road, not whichever the hash yields"
    assert_select "input[data-find-target=box]"
  end

  test "a loose match says so; nothing at all points at capture" do
    sign_in @pm
    # close enough to list, not close enough to claim it answers the question
    loose = Capture::Find.call("ridge zzzzqx", viewer: @pm)
    assert loose[:loose], "one word of two, and only in the instructions: related, not an answer"
    assert_equal "skills", loose[:best].group
    get find_path(q: "ridge zzzzqx")
    assert_select "p", text: /Nothing answers that exactly/

    assert_equal 0, Capture::Find.call("zzzzqx", viewer: @pm)[:total]
    get find_path(q: "zzzzqx")
    assert_select "a[href=?]", prompts_path, text: /record it once in Office/
  end
end
