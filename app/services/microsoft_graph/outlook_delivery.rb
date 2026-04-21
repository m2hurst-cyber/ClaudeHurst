module MicrosoftGraph
  class OutlookDelivery
    def initialize(connection)
      @client = Client.new(connection: connection)
    end

    def deliver(to:, subject:, html:, cc: [])
      client.post("/me/sendMail", {
        message: {
          subject: subject,
          body: {
            contentType: "HTML",
            content: html
          },
          toRecipients: Array(to).map { |address| address_payload(address) },
          ccRecipients: Array(cc).map { |address| address_payload(address) }
        },
        saveToSentItems: true
      })
    end

    private

    attr_reader :client

    def address_payload(address)
      { emailAddress: { address: address } }
    end
  end
end
