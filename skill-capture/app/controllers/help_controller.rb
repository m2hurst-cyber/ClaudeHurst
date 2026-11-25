# The help centre. Guides and FAQ come from files in help/, so fixing the help is a text
# edit rather than a deploy, and every page has a Markdown form agents can read.
class HelpController < ApplicationController
  def index
    @query = params[:q].to_s.strip
    @hits = Capture::Help.search(@query) if @query.present?
    @by_section = Capture::Help.by_section
    @topics = Capture::Help.topics
    @tour = Capture::Onboarding.for(current_user)
    respond_to do |format|
      format.html
      format.md { render_markdown(index_markdown, "skill-capture-help") }
    end
  end

  def show
    @guide = Capture::Help.find(params[:slug]) or return redirect_to(help_path, alert: "No such guide.")
    @related = Capture::Help.guides.select { |g| g.slug != @guide.slug && (g.tags & @guide.tags).any? }.first(3)
    @questions = Capture::Help.faq.select { |f| f.guide == @guide.slug }
    respond_to do |format|
      format.html
      format.md { render_markdown(@guide.to_markdown, @guide.slug) }
    end
  end

  private

  # The whole help centre as one document, for pasting into a model.
  def index_markdown
    out = ["# Skill Capture help", ""]
    Capture::Help.by_section.each do |section, guides|
      out << "## #{Capture::Help::SECTIONS.fetch(section, section.humanize)}" << ""
      guides.each { |g| out << "### #{g.title}" << "" << g.summary << "" << g.body << "" }
    end
    out << "## Frequently asked" << ""
    Capture::Help.topics.each do |topic, questions|
      out << "### #{topic}" << ""
      questions.each { |q| out << "**#{q.question}**" << "" << q.answer.to_s << "" }
    end
    out.join("\n")
  end
end
