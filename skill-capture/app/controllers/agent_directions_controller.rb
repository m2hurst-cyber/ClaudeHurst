# The firm's written directions for agents: how big a skill should be here, and how to
# write one at that size. Served as Markdown first, because its readers are agents.
class AgentDirectionsController < ApplicationController
  def index
    @level = Capture::Granularity.firm_level
    @levels = Capture::Granularity::LEVELS
    @overrides = GranularityOverride.domains
    respond_to do |format|
      format.html
      format.md { render_markdown(all_markdown, "granularity-directions") }
    end
  end

  def show
    key = params[:key].to_s
    @level = Capture::Granularity::LEVELS.find { |_, s| s[:key] == key }&.first
    return redirect_to(agent_directions_path, alert: "No directions for #{key}.") unless @level

    @settings = Capture::Granularity.settings(@level)
    @directions = Capture::Granularity.directions(@level)
    @active = @level == Capture::Granularity.firm_level
    respond_to do |format|
      format.html
      format.md { render_markdown(@directions, "granularity-#{key}") }
    end
  end

  private

  def all_markdown
    active = Capture::Granularity.firm_level
    out = ["# Granularity directions", "",
           "How this firm cuts work into skills. The firm is currently set to " \
           "**#{Capture::Granularity.label(active)}**.", ""]
    GranularityOverride.domains.each { |o| out << "- The #{o.scope_key} area uses **#{o.label}**." }
    out << ""
    Capture::Granularity::LEVELS.each_key { |level| out << Capture::Granularity.directions(level) << "" }
    out.join("\n")
  end
end
