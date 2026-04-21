module MicrosoftGraph
  class OutlookCalendar
    def initialize(connection)
      @client = Client.new(connection: connection)
    end

    def create_event(subject:, starts_at:, ends_at:, body:, attendees: [])
      client.post("/me/events", {
        subject: subject,
        body: {
          contentType: "HTML",
          content: body
        },
        start: {
          dateTime: starts_at.iso8601,
          timeZone: Time.zone.tzinfo.name
        },
        end: {
          dateTime: ends_at.iso8601,
          timeZone: Time.zone.tzinfo.name
        },
        attendees: Array(attendees).map { |address| attendee_payload(address) }
      })
    end

    private

    attr_reader :client

    def attendee_payload(address)
      {
        emailAddress: { address: address },
        type: "required"
      }
    end
  end
end
