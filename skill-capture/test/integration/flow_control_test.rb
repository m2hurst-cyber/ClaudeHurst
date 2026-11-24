require "test_helper"

# Controlling a flow: pauses (until resumed, or timed), holding the whole run, starting from any task,
# running just one, deploying a task mid-sequence, skipping, inserting tasks or pauses into a live run.
class FlowControlTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  setup do
    @rae = make_user(role: "member", domains: %w[finance], name: "Rae")
    @dee = make_user(role: "member", domains: %w[finance], name: "Dee")
    @agent, @agent_token = Source.issue!(name: "Agent", kind: "integration")
    @flow = Flow.create!(user: @rae, name: "Five", steps: Flow.normalize_steps([
      { id: "t1", title: "Collect", app: "Excel" },
      { id: "p1", kind: "pause", pause_mode: "manual" },
      { id: "t2", title: "Analyze", app: "Excel", assignee: "agent:#{@agent.id}" },
      { id: "p2", kind: "pause", pause_mode: "timer", pause_minutes: 30 },
      { id: "t3", title: "Deck", app: "PowerPoint", assignee: "user:#{@dee.id}" }
    ]))
  end

  def states(run) = run.reload.steps.map { |s| s["state"] }

  test "pauses: a manual one waits to be resumed; a timed one resumes itself; nothing is sent for a pause" do
    assert_equal ["Pause", "manual", nil], @flow.steps[1].values_at("title", "pause_mode", "pause_minutes")
    run = FlowRun.start!(@flow, user: @rae)
    run.complete!(index: 0, user: @rae)
    assert_equal %w[done paused pending pending pending], states(run)
    assert Notification.exists?(user: @rae, title: "Paused: Pause")
    assert_raises(FlowRun::Error) { run.complete!(index: 1, user: @rae) }
    assert_raises(FlowRun::Error) { run.resume_pause!(index: 1, by: @dee) }
    run.resume_pause!(index: 1, by: @rae)
    assert_equal %w[done done ready pending pending], states(run)
    assert_equal 1, AddinCommand.where(target_source: @agent, kind: "flow_task").count

    assert_enqueued_with(job: FlowResumeJob) { run.complete!(index: 2, source: @agent) }
    assert_equal "paused", run.reload.steps[3]["state"]
    FlowResumeJob.perform_now(run.id, 3)
    assert_equal "paused", run.reload.steps[3]["state"], "not due yet"
    travel 31.minutes do
      FlowResumeJob.perform_now(run.id, 3)
      assert_equal %w[done done done done ready], states(run)
      assert_equal "Timer", run.steps[3]["by"]
    end
  end

  test "holding the run blocks completion and handoffs; a timer that came due resumes on release" do
    run = FlowRun.start!(@flow, user: @rae, from: 2)
    assert_raises(FlowRun::Error) { run.hold!(by: @dee) }
    run.hold!(by: @rae)
    e = assert_raises(FlowRun::Error) { run.complete!(index: 2, source: @agent) }
    assert_match(/paused/, e.message)
    run.release!(by: @rae)
    run.complete!(index: 2, source: @agent)
    run.hold!(by: @rae)
    travel 40.minutes do
      FlowResumeJob.perform_now(run.id, 3)
      assert_equal "paused", run.reload.steps[3]["state"], "held: the timer waits"
      run.release!(by: @rae)
      assert_equal %w[skipped skipped done done ready], states(run)
    end
  end

  test "start anywhere, run just one task, deploy mid-sequence (forward and back), skip, insert" do
    only = FlowRun.start!(@flow, user: @rae, from: 2, only: true)
    assert_equal %w[skipped skipped ready skipped skipped], states(only)
    only.complete!(index: 2, user: @rae) # the owner stands in for the agent
    assert_equal "completed", only.reload.status

    run = FlowRun.start!(@flow, user: @rae)
    first = AddinCommand.where(target_user: @rae, kind: "flow_task").order(:id).last
    run.jump_to!(4, by: @rae)
    assert_equal %w[skipped skipped skipped skipped ready], states(run)
    assert_equal "cancelled", first.reload.status, "the task taken off the current slot is withdrawn"
    assert AddinCommand.pending.exists?(target_user: @dee, kind: "flow_task")
    run.jump_to!(0, by: @rae)
    assert_equal %w[ready pending pending pending pending], states(run)
    assert_raises(FlowRun::Error) { run.jump_to!(2, by: @dee) }

    run.insert!(after: 0, step: { kind: "task", title: "Check sources", app: "Excel" }, by: @rae)
    run.insert!(after: 1, step: { kind: "pause", pause_mode: "timer", pause_minutes: 5 }, by: @rae)
    assert_equal ["Collect", "Check sources", "Pause", "Pause", "Analyze"], run.reload.steps.first(5).map { |s| s["title"] }
    assert_raises(FlowRun::Error) { run.insert!(after: 0, step: { title: "" }, by: @rae) }
    run.skip!(1, by: @rae)
    run.complete!(index: 0, user: @rae)
    assert_equal %w[done skipped paused], states(run).first(3)
    run.skip!(2, by: @rae)
    assert_equal "paused", states(run)[3], "skipping the current pause moves on to the next step"
    assert_raises(FlowRun::Error) { run.skip!(0, by: @rae) }
  end

  test "console: run page controls, live status on the process map, run from a task" do
    run = FlowRun.start!(@flow, user: @rae)
    sign_in @rae
    get flow_run_path(run)
    assert_select "[role=status]", text: /Running now: task 1, Collect/
    assert_select "svg[aria-label*='1. Collect: ready (current)']"
    assert_select "button", text: "⏸ Pause run"
    assert_select "button", text: "Deploy now", count: 2
    post jump_flow_run_path(run, step: 4)
    assert_equal 4, run.reload.current_index
    post insert_flow_run_path(run, after: 4), params: { kind: "pause", pause_mode: "manual" }
    assert_equal "pause", run.reload.steps.last["kind"]
    get flow_run_path(run)
    assert_select "svg g text", text: /⏸ Pause/
    run.insert!(after: 5, step: { kind: "pause" }, by: @rae)
    assert_equal run.reload.steps[5]["app"], run.steps[6]["app"], "a step inserted without a lane takes the lane before it"
    post hold_flow_run_path(run)
    get flow_run_path(run)
    assert_select "[role=status]", text: /Run on hold/
    get flow_run_path(run, format: :json)
    assert_equal "on_hold", response.parsed_body["status"]

    get flow_path(@flow)
    live = JSON.parse(css_select("[data-controller=flow-map]").first["data-flow-map-run-value"])
    assert_equal [4, "on_hold"], live.values_at("current_index", "status")
    assert_select "[data-flow-map-target=paletteItem][data-text='pause wait']"

    post run_flow_path(@flow, from: 2, only: 1)
    r2 = FlowRun.order(:id).last
    assert_equal [2, %w[skipped skipped ready skipped skipped]], [r2.current_index, r2.steps.map { |s| s["state"] }]

    sign_in @dee
    post hold_flow_run_path(run)
    assert_equal "on_hold", run.reload.status
    follow_redirect!
    assert_select "button", text: "⏸ Pause run", count: 0
  end

  test "add-in API: start from a task, pause, resume, deploy now, insert a pause" do
    h = { "Authorization" => "Bearer #{AddinToken.issue!(user: @rae, host: 'Excel').last}", "Content-Type" => "application/json" }
    post "/api/v1/addin/flow_runs", params: { flow_id: @flow.id, from: 1 }.to_json, headers: h
    id = response.parsed_body["id"]
    assert_equal ["paused", true], [response.parsed_body["steps"][1]["state"], response.parsed_body["owner"]]
    post "/api/v1/addin/flow_runs/#{id}/resume?step=1", params: {}.to_json, headers: h
    assert_equal 2, response.parsed_body["current_index"]
    post "/api/v1/addin/flow_runs/#{id}/insert", params: { after: 2, kind: "pause" }.to_json, headers: h
    assert_equal "pause", response.parsed_body["steps"][3]["kind"]
    post "/api/v1/addin/flow_runs/#{id}/hold", params: {}.to_json, headers: h
    assert_equal "on_hold", response.parsed_body["status"]
    post "/api/v1/addin/flow_runs/#{id}/jump?step=5", params: {}.to_json, headers: h
    assert_equal 5, response.parsed_body["current_index"]
    post "/api/v1/addin/flow_runs/#{id}/jump?step=9", params: {}.to_json, headers: h
    assert_response :unprocessable_entity
  end
end
