# Connecting, testing and running a person's own backup. Theirs alone: nobody else's
# backup is reachable from here, including an admin's.
class GitBackupsController < ApplicationController
  before_action :refuse_unless_allowed
  before_action :load_backup, only: %i[update destroy push]

  def create
    @backup = current_user.build_git_backup(backup_params)
    if @backup.save && check(@backup)
      AuditLog.record("git_backup.connected", user: current_user, subject: @backup, repo: @backup.repo)
      GitBackupJob.perform_later(@backup.id)
      redirect_to settings_path, notice: "Connected to #{@backup.repo}. The first backup is on its way."
    else
      redirect_to settings_path, alert: @backup.errors.full_messages.to_sentence.presence || @backup.last_error
    end
  end

  def update
    attrs = backup_params
    attrs = attrs.except(:token) if attrs[:token].blank? # keep the token you already gave us
    if @backup.update(attrs)
      redirect_to settings_path, notice: "Saved."
    else
      redirect_to settings_path, alert: @backup.errors.full_messages.to_sentence
    end
  end

  def push
    GitBackupJob.perform_later(@backup.id)
    redirect_to settings_path, notice: "Backing up to #{@backup.repo} now."
  end

  def destroy
    repo = @backup.repo
    @backup.destroy!
    AuditLog.record("git_backup.disconnected", user: current_user, repo: repo)
    redirect_to settings_path, notice: "Disconnected. Nothing was removed from #{repo}."
  end

  private

  # Not an endless method: `def x = a or b` binds the `or` to the definition, not the
  # value, so the guard silently never fires.
  def load_backup
    @backup = current_user.git_backup
    redirect_to(settings_path, alert: "No backup is connected.") if @backup.nil?
  end

  def refuse_unless_allowed
    redirect_to settings_path, alert: "Personal backups are turned off for this firm." unless GitBackup.allowed?
  end

  # Fail at the point of connecting rather than silently in a job an hour later.
  def check(backup)
    Capture::GitPush.new(backup).check!
    true
  rescue Capture::GitPush::Error => e
    backup.update_columns(last_error: e.message)
    backup.errors.add(:base, e.message)
    false
  end

  def backup_params = params.require(:git_backup).permit(:repo, :branch, :path_prefix, :token, :enabled)
end
