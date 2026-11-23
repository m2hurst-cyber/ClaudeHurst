# Runs the save / extend / branch triggers for one person and has the AI evaluate what they find.
# Queued by the add-in's event uploads at most every N minutes per person (Protocol "evaluation").
class PromptCheckJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    user = User.active.find_by(id: user_id) or return
    user.update_columns(prompts_checked_at: Time.current)
    Capture::Prompter.call(user)
  end

  # Queue a check unless one ran (or was queued) within the interval. Returns true when queued.
  def self.request(user)
    every = Protocol.for("evaluation")["interval_minutes"].minutes
    return false if user.prompts_checked_at && user.prompts_checked_at > every.ago
    # Claim the slot first so concurrent uploads queue one job, not several.
    claimed = User.where(id: user.id).where("prompts_checked_at IS NULL OR prompts_checked_at <= ?", every.ago)
                  .update_all(prompts_checked_at: Time.current)
    return false if claimed.zero?
    perform_later(user.id)
    true
  end
end
