# The first-run walkthrough. Every step is a real thing to do and ticks itself off when the
# person has done it, so nobody is clicking "next" through screens they will not remember.
class TourController < ApplicationController
  def show
    current_user.update_column(:tour_seen_at, Time.current) if current_user.tour_seen_at.nil?
    @tour = Capture::Onboarding.for(current_user)
  end

  # "I'll explore on my own." Stops the nudge; the tour stays at /start for whenever they want it.
  def dismiss
    current_user.update!(tour_dismissed_at: Time.current)
    redirect_to root_path, notice: "Tour put away. It's under Help whenever you want it."
  end

  def restart
    current_user.update!(tour_dismissed_at: nil)
    redirect_to tour_path
  end
end
