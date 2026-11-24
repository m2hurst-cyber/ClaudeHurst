class SkillsController < ApplicationController
  before_action :set_skill, only: %i[show edit update download deprecate compare audience]

  def index
    authorize Skill
    scope = (params[:all] == "1" ? Skill.all : Skill.published).visible_to(current_user)
    scope = scope.where(domain: params[:domain]) if params[:domain].present?
    scope = scope.where(stage: params[:stage]) if Skill::STAGES.include?(params[:stage])
    scope = scope.at_level(params[:level], current_user) if Skill::LEVELS.include?(params[:level])
    scope = scope.classified_as(app: params[:app].presence_in(SkillClassification::APPS), field: params[:field].presence)
    @field = Field.find_by(path: params[:field]) if params[:field].present?
    @domains = Skill.published.distinct.where.not(domain: nil).order(:domain).pluck(:domain)
    @pagy, @skills = pagy(scope.search(params[:q]).recent)
    @classifications = SkillClassification.includes(:field, :updated_by).where(skill_name: @skills.map(&:name)).index_by(&:skill_name)
  end

  def show; end

  # Which process is better? The skill and its alternatives (same lineage), side by side.
  def compare
    @family = @skill.family.select { |s| s.visible_to?(current_user) }
    @rows = Capture::Voting.comparison(@family)
  end

  # Admins choose who a market skill is shared with: the firm's industry, or everyone.
  def audience
    raise Pundit::NotAuthorizedError unless current_user.admin? && @skill.stage == "market"
    @skill.update!(market_audience: params[:market_audience].to_s.presence_in(Skill::MARKET_AUDIENCES) || "global")
    AuditLog.record("skill.audience", user: current_user, subject: @skill, audience: @skill.market_audience)
    redirect_to skill_path(@skill), notice: "Shared with #{@skill.market_audience == 'industry' ? 'our industry' : 'everyone'}."
  end

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
