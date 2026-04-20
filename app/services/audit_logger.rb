class AuditLogger
  def self.record(user:, action:, subject: nil, metadata: {})
    AuditLog.create!(
      user: user,
      action: action,
      subject: subject,
      metadata: metadata
    )
  rescue => e
    Rails.logger.error("AuditLogger failed: #{e.class}: #{e.message}")
  end
end
