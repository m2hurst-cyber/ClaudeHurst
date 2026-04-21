module MicrosoftGraph
  class TeamsNotifier
    def initialize(connection)
      @client = Client.new(connection: connection)
    end

    def post_channel_message(team_id:, channel_id:, title:, body:, url: nil)
      html = ["<strong>#{ERB::Util.html_escape(title)}</strong>", ERB::Util.html_escape(body).gsub("\n", "<br>")]
      html << %(<br><a href="#{ERB::Util.html_escape(url)}">Open in ClaudeHurst</a>) if url.present?

      client.post("/teams/#{team_id}/channels/#{channel_id}/messages", {
        body: {
          contentType: "html",
          content: html.join("<br>")
        }
      })
    end

    private

    attr_reader :client
  end
end
