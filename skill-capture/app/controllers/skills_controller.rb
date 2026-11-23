class SkillsController < ApplicationController
  before_action :set_skill, only: %i[show edit update download deprecate]

  def index
    authorize Skill
    scope = params[:all] == "1" ? Skill.all : Skill.published
    scope = scope.where(domain: params[:domain]) if params[:domain].present?
    @domains = Skill.published.distinct.where.not(domain: nil).order(:domain).pluck(:domain)
    @pagy, @skills = pagy(scope.search(params[:q]).recent)
  end

  def show; end

  def download
    send_data @skill.to_skill_md, filename: "SKILL.md", type: "text/markdown", disposition: "attachment"
  end

  def edit; end

  # Never overwrites: same name → next version, new name → fork.
  def update
    attrs = params.require(:skill).permit(:name, :title, :description, :body, :tags, :change_note).to_h.symbolize_keys
    attrs[:tags] = attrs[:tags].to_s.split(",").map { |t| t.strip.parameterize }.reject(&:blank?) if attrs.key?(:tags)
    new_skill = Capture::Publisher.revise!(@skill, editor: current_user, attrs: attrs)
    redirect_to new_skill, notice: "Saved as #{new_skill.name} v#{new_skill.version}."
  rescue Capture::Publisher::Error, ActiveRecord::RecordInvalid => e
    flash.now[:alert] = e.message
    render :edit, status: :unprocessable_entity
  end

  def deprecate
    @skill.update!(status: "deprecated")
    AuditLog.record("skill.deprecated", user: current_user, subject: @skill)
    redirect_to @skill, notice: "Skill deprecated."
  end

  private

  def set_skill
    @skill = Skill.find(params[:id])
    authorize @skill
  end
end
