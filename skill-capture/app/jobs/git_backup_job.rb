# Pushing to someone else's server takes as long as it takes; the person should not be
# watching a spinner for it.
class GitBackupJob < ApplicationJob
  queue_as :default

  def perform(backup_id)
    backup = GitBackup.find_by(id: backup_id) or return
    return unless GitBackup.allowed? && backup.enabled?

    files = Capture::GitExport.files(backup)
    result = Capture::GitPush.call(backup, files, message: Capture::GitExport.commit_message(files.size - 2))
    backup.update!(last_pushed_at: Time.current, last_commit_sha: result.commit_sha,
                   last_skill_count: files.size - 2, last_error: nil)
    AuditLog.record("git_backup.pushed", user: backup.user, subject: backup,
                    repo: backup.repo, skills: backup.last_skill_count, commit: result.commit_sha)
    Notification.create!(user: backup.user, subject: backup, kind: "git_backup",
                         title: "Backed up #{backup.last_skill_count} #{'skill'.pluralize(backup.last_skill_count)} to #{backup.repo}",
                         url: Rails.application.routes.url_helpers.settings_path)
  rescue Capture::GitPush::Error => e
    backup&.update(last_error: e.message)
    AuditLog.record("git_backup.failed", user: backup&.user, subject: backup, repo: backup&.repo, error: e.message)
  end
end
