class SkillsController < ApplicationController
  before_action :set_skill, only: %i[show edit update download deprecate]

  def index
    authorize Skill
    scope = params[:all] == "1" ? Skill.all : Skill.published
    scope = scope.where(domain: params[:domain]) if params[:domain].present?
    scope = scope.search(params[:q]).recent
    respond_to do |format|
      format.html { @pagy, @skills = pagy(scope) }
      format.json { render json: scope.limit(500).map { |s| skill_json(s) } }
    end
  end

  def show
    respond_to do |format|
      format.html
      format.json { render json: skill_json(@skill).merge(body: @skill.body, skill_md: @skill.to_skill_md) }
    end
  end

  def download
    send_data @skill.to_skill_md, filename: "SKILL.md", type: "text/markdown", disposition: "attachment"
  end

  def edit; end

  # Editing an official skill never overwrites it: it creates a new version
  # (same name) or a fork (new name), with a parent link for lineage.
  def update
    attrs = params.require(:skill).permit(:name, :title, :description, :body, :tags, :change_note).to_h.symbolize_keys
    attrs[:tags] = attrs[:tags].to_s.split(",").map { |t| t.strip.downcase.tr(" ", "-") }.reject(&:blank?) if attrs.key?(:tags)
    new_skill = SkillCapture::Publisher.revise!(@skill, editor: current_user, attrs: attrs)
    redirect_to new_skill, notice: "Saved as #{new_skill.name} v#{new_skill.version}."
  rescue SkillCapture::Publisher::Error, ActiveRecord::RecordInvalid => e
    flash.now[:alert] = e.message
    render :edit, status: :unprocessable_entity
  end

  def deprecate
    @skill.update!(status: "deprecated")
    AuditLogger.record(user: current_user, action: "skill.deprecated", subject: @skill)
    redirect_to @skill, notice: "Skill deprecated."
  end

  private

  def set_skill
    @skill = Skill.find(params[:id])
    authorize @skill
  end

  def skill_json(s)
    s.slice(:id, :name, :version, :title, :description, :domain, :tags, :status, :license, :published_at, :parent_skill_id)
     .merge(source: s.source.except("contributor_ids"), url: skill_url(s, format: :json),
            download_url: download_skill_url(s))
  end
end
