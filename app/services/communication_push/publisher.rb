module CommunicationPush
  class Publisher
    def self.call(...)
      new.call(...)
    end

    def call(event_type:, channel:, subject: nil, user: nil, recipient: nil, payload: {})
      deduplication_key = payload[:deduplication_key].presence || default_key(event_type, channel, subject, recipient, payload)

      event = CommunicationPushEvent.find_or_create_by!(deduplication_key: deduplication_key) do |record|
        record.event_type = event_type
        record.channel = channel
        record.subject = subject
        record.user = user
        record.recipient = recipient
        record.payload = payload
        record.status = "pending"
      end

      CommunicationPushJob.perform_later(event.id) if event.status == "pending"
      event
    end

    private

    def default_key(event_type, channel, subject, recipient, payload)
      parts = [event_type, channel, subject&.class&.name, subject&.id, recipient, payload.except(:body, :html).to_json]
      Digest::SHA256.hexdigest(parts.compact.join(":"))
    end
  end
end
