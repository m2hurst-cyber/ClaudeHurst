# Ends a timed pause in a flow run when it's due, and hands off to the next task.
class FlowResumeJob < ApplicationJob
  queue_as :default

  def perform(run_id, index)
    run = FlowRun.find_by(id: run_id) or return
    return unless run.active? && run.current_index == index && run.steps[index]&.dig("state") == "paused"
    run.resume_pause!(index: index)
  end
end
