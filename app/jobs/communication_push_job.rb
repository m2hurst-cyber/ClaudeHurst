class CommunicationPushJob < ApplicationJob
  queue_as :default

  def perform(event_id)
    event = CommunicationPushEvent.find(event_id)
    return unless event.status == "pending"

    case event.channel
    when "teams"
      deliver_teams(event)
    when "email"
      deliver_email(event)
    when "calendar"
      deliver_calendar(event)
    else
      event.failed!("Unsupported communication channel: #{event.channel}")
    end
  rescue StandardError => e
    event&.failed!(e.message)
    raise
  end

  private

  def deliver_teams(event)
    connection = connection_for(event)
    payload = event.payload.symbolize_keys

    MicrosoftGraph::TeamsNotifier.new(connection).post_channel_message(
      team_id: payload.fetch(:team_id),
      channel_id: payload.fetch(:channel_id),
      title: payload.fetch(:title),
      body: payload.fetch(:body),
      url: payload[:url]
    )

    event.delivered!
  end

  def deliver_email(event)
    connection = connection_for(event)
    payload = event.payload.symbolize_keys

    MicrosoftGraph::OutlookDelivery.new(connection).deliver(
      to: event.recipient || payload.fetch(:to),
      subject: payload.fetch(:subject),
      html: payload.fetch(:html),
      cc: payload.fetch(:cc, [])
    )

    event.delivered!
  end

  def deliver_calendar(event)
    connection = connection_for(event)
    payload = event.payload.symbolize_keys

    response = MicrosoftGraph::OutlookCalendar.new(connection).create_event(
      subject: payload.fetch(:subject),
      starts_at: Time.zone.parse(payload.fetch(:starts_at)),
      ends_at: Time.zone.parse(payload.fetch(:ends_at)),
      body: payload.fetch(:body),
      attendees: payload.fetch(:attendees, [])
    )

    event.update!(external_id: response["id"]) if response["id"].present?
    event.delivered!
  end

  def connection_for(event)
    user = event.user || event.subject.try(:owner) || User.admin.first
    connection = user&.microsoft_connection&.kept
    raise "No connected Microsoft account is available for this push event" unless connection&.connected?

    connection
  end
end
