# The MCP endpoint: POST /mcp, JSON-RPC 2.0 over HTTP, so any agent that speaks MCP can use the skill
# library, follow the map, pick up the work addressed to it, run a job and report what it cost.
#
#   Authorization: Bearer sc_...   an agent (a Source integration token): shared skills, its own tasks
#   Authorization: Bearer sca_...  a person (an add-in token): what that person can see, and can act as them
class McpController < ActionController::API
  VERSION = "2025-06-18".freeze          # the protocol version we implement; a client's own is echoed back
  SERVER = { name: "skill-capture", title: "Skill Capture", version: "1" }.freeze

  before_action :authenticate!

  def handle
    body = request.request_parameters
    return render(json: batch(body)) if body.is_a?(Array)
    result = handle_message(body)
    result.nil? ? head(:accepted) : render(json: result) # a notification gets no reply
  end

  # A plain GET is a person poking the URL in a browser, or a client checking the endpoint exists.
  def discover
    render json: { server: SERVER, protocol_version: VERSION, transport: "streamable-http (JSON responses)",
                   authenticate_with: "Authorization: Bearer <integration token or add-in token>",
                   tools: Mcp::Registry.tools.map { |t| { name: t[:name], title: t[:title], description: t[:description] } } }
  end

  private

  def batch(list) = list.filter_map { |m| handle_message(m) }

  # Rails' own #dispatch is the controller entry point, so this one is named for what it does.
  def handle_message(message)
    m = message.to_h.with_indifferent_access
    id = m[:id]
    case m[:method]
    when "initialize" then reply(id, initialize_result(m))
    when "ping" then reply(id, {})
    when "tools/list" then reply(id, { tools: Mcp::Registry.tools.map { |t| schema_for(t) } })
    when "tools/call" then reply(id, call_tool(m[:params] || {}))
    when %r{\Anotifications/} then nil
    else error(id, -32_601, "This server has no method #{m[:method]}")
    end
  rescue Mcp::Registry::Error => e
    error(id, e.code, e.message)
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    error(id, -32_000, e.message)
  rescue StandardError => e
    Rails.logger.error("MCP #{m&.dig(:method)}: #{e.class}: #{e.message}")
    error(id, -32_603, "#{e.class}: #{e.message}")
  end

  def initialize_result(m)
    { protocolVersion: m.dig(:params, :protocolVersion).presence || VERSION,
      capabilities: { tools: { listChanged: false } },
      serverInfo: SERVER,
      instructions: "Skill Capture holds how this company actually does its work: reviewed skills, the map of how they " \
                    "connect, playbooks for a job or a return, and the flows that hand work between people and agents. " \
                    "Search before you invent a method; report what every run cost with report_usage; and when a task " \
                    "could be a deterministic script, hand the script over so it stops costing tokens." }
  end

  def schema_for(t)
    { name: t[:name], title: t[:title], description: t[:description],
      inputSchema: t[:input_schema].deep_stringify_keys }
  end

  def call_tool(params)
    name = params[:name].to_s
    started = Time.current
    data = Mcp::Registry.call(name, params[:arguments], context)
    AuditLog.record("mcp.call", user: @user, source: @source, tool: name, ms: ((Time.current - started) * 1000).round)
    { content: [{ type: "text", text: JSON.pretty_generate(data) }], structuredContent: data, isError: false }
  rescue Mcp::Registry::Error => e
    AuditLog.record("mcp.refused", user: @user, source: @source, tool: name, reason: e.message)
    { content: [{ type: "text", text: e.message }], isError: true }
  end

  def context = { user: @user, source: @source, host: request.base_url }

  def reply(id, result) = { jsonrpc: "2.0", id: id, result: result }
  def error(id, code, message) = { jsonrpc: "2.0", id: id, error: { code: code, message: message } }

  def authenticate!
    token = request.authorization.to_s[/\ABearer (.+)\z/, 1]
    @source = Source.authenticate(token)
    @user = AddinToken.authenticate(token)&.user unless @source
    return if @source || @user
    render json: { jsonrpc: "2.0", id: nil, error: { code: -32_001, message: "Connect with an integration token (Admin → Integrations) or an add-in token" } },
           status: :unauthorized
  end
end
