class SkillCandidatesController < ApplicationController
  before_action :set_candidate, only: %i[show edit update generate_draft approve reject dismiss]

  def index
    authorize SkillCandidate
    @status = params[:status].presence_in(SkillCandidate::STATUSES + ["all"]) || "open"
    scope = policy_scope(SkillCandidate).recent
    scope = @status == "open" ? scope.open : (@status == "all" ? scope : scope.where(status: @status))
    @metrics = SkillCapture::Metrics.summary
    respond_to do |format|
      format.html { @pagy, @candidates = pagy(scope) }
      format.json { render json: scope.limit(200).map { |c| candidate_json(c) } }
    end
  end

  def show
    respond_to do |format|
      format.html
      format.json { render json: candidate_json(@candidate, full: true) }
    end
  end

  # Manual "please capture this" request — the non-detected path into the same review queue.
  def new
    @candidate = SkillCandidate.new(domain: current_user.admin? ? "general" : current_user.role, origin: "manual")
    authorize @candidate
  end

  def create
    @candidate = SkillCandidate.new(manual_params.merge(
      origin: "manual",
      signature: "manual:#{SecureRandom.hex(8)}",
      requested_by: current_user,
      contributor_ids: [current_user.id],
      occurrence_count: 1,
      distinct_user_count: 1,
      first_seen_at: Time.current,
      last_seen_at: Time.current
    ))
    @candidate.steps = Array(params.dig(:skill_candidate, :steps)).reject(&:blank?) & SkillCapture::Catalog::STEPS.keys
    @candidate.draft_name = @candidate.draft_title.to_s.parameterize.first(64) if @candidate.draft_name.blank?
    if @candidate.draft_body.present?
      @candidate.assign_attributes(status: "drafted", draft_generator: "human", drafted_at: Time.current)
    end
    authorize @candidate
    if @candidate.save
      AuditLogger.record(user: current_user, action: "skill_candidate.requested", subject: @candidate)
      @candidate.notify_reviewers!("Skill requested by #{current_user.display_name}: #{@candidate.display_title}")
      respond_to do |format|
        format.html { redirect_to @candidate, notice: "Skill request submitted for review." }
        format.json { render json: candidate_json(@candidate, full: true), status: :created }
      end
    else
      respond_to do |format|
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: { errors: @candidate.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def edit; end

  def update
    attrs = draft_params
    attrs[:draft_tags] = split_list(attrs[:draft_tags]) if attrs.key?(:draft_tags)
    attrs[:draft_inputs] = split_lines(attrs[:draft_inputs]) if attrs.key?(:draft_inputs)
    attrs[:draft_outputs] = split_lines(attrs[:draft_outputs]) if attrs.key?(:draft_outputs)
    attrs[:draft_generator] = "human" if attrs[:draft_body].present? && @candidate.draft_generator.blank?
    attrs[:status] = "drafted" if @candidate.status == "detected" && attrs[:draft_body].present?
    if @candidate.update(attrs)
      AuditLogger.record(user: current_user, action: "skill_candidate.edited", subject: @candidate)
      redirect_to @candidate, notice: "Draft saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def generate_draft
    SkillCapture::DraftGenerator.call(@candidate)
    redirect_to @candidate, notice: "Draft generated (#{@candidate.draft_generator})."
  end

  def approve
    skill = SkillCapture::Publisher.publish!(@candidate, reviewer: current_user)
    respond_to do |format|
      format.html { redirect_to skill, notice: "Published #{skill.name} v#{skill.version}." }
      format.json { render json: { skill_id: skill.id, name: skill.name, version: skill.version }, status: :created }
    end
  rescue SkillCapture::Publisher::Error, ActiveRecord::RecordInvalid => e
    respond_to do |format|
      format.html { redirect_to @candidate, alert: e.message }
      format.json { render json: { error: e.message }, status: :unprocessable_entity }
    end
  end

  def reject = close_as("rejected")
  def dismiss = close_as("dismissed")

  private

  def set_candidate
    @candidate = SkillCandidate.find(params[:id])
    authorize @candidate
  end

  def close_as(status)
    @candidate.update!(status: status, reviewer: current_user, reviewed_at: Time.current,
                       review_notes: params[:review_notes].presence || @candidate.review_notes)
    AuditLogger.record(user: current_user, action: "skill_candidate.#{status}", subject: @candidate,
                       metadata: { notes: @candidate.review_notes })
    redirect_to skill_candidates_path, notice: "Candidate #{status}."
  end

  def manual_params
    params.require(:skill_candidate).permit(:domain, :draft_title, :draft_name, :draft_description, :draft_body)
  end

  def draft_params
    params.require(:skill_candidate).permit(:draft_name, :draft_title, :draft_description, :draft_body,
                                            :draft_tags, :draft_inputs, :draft_outputs, :review_notes)
  end

  def split_list(v) = v.to_s.split(/[,\n]/).map { |t| t.strip.downcase.tr(" ", "-") }.reject(&:blank?).uniq
  def split_lines(v) = v.to_s.split("\n").map(&:strip).reject(&:blank?)

  def candidate_json(c, full: false)
    data = c.slice(:id, :status, :origin, :domain, :steps, :occurrence_count, :distinct_user_count,
                   :first_seen_at, :last_seen_at, :draft_name, :draft_title, :draft_description, :skill_id)
    data = data.merge(c.slice(:draft_body, :draft_tags, :draft_inputs, :draft_outputs, :draft_generator,
                              :example_traces, :review_notes, :reviewed_at)) if full
    data.merge(url: skill_candidate_url(c, format: :json))
  end
end
