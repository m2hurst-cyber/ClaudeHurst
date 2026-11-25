# A person's own settings. Small on purpose: the things someone needs to change about how
# the system treats them, without asking an admin.
class SettingsController < ApplicationController
  def show
    @level = Capture::Granularity.level_for(domain: area, user: current_user)
    @personal = GranularityOverride.find_by(scope: "user", scope_key: current_user.id.to_s)
    @inherited = Capture::Granularity.level_for(domain: area)
    @tour = Capture::Onboarding.for(current_user)
  end

  def update
    level = params[:granularity].presence
    GranularityOverride.set!("user", current_user.id, level == "inherit" ? nil : level)
    AuditLog.record("settings.updated", user: current_user, granularity: level)
    redirect_to settings_path, notice: level == "inherit" ? "Back to your area's setting." : "Saved."
  end

  private

  def area = current_user.domains.first
end
