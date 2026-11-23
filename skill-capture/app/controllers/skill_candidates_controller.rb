class SkillCandidatesController < ApplicationController
  before_action :set_candidate, only: %i[show edit update generate_draft approve reject dismiss]

  def index
    authorize SkillCandidate
    @status = params[:status].presence_in(SkillCandidate::STATUSES + %w[open all]) || "open"
    scope = policy_scope(SkillCandidate).recent
    scope = { "open" => scope.open, "all" => scope }.fetch(@status) { scope.where(status: @status) }
    @metrics = Capture::Metrics.summary
    @pagy, @candidates = pagy(scope)
  end

  def show; end

  # Manual "please capture this" request: same review queue as detected workflows.
  def new
    @candidate = SkillCandidate.new(domain: current_user.domains.first, origin: "manual")
    if (@fix = Skill.current(params[:fix].to_s))
      @candidate.assign_attributes(domain: @fix.domain, draft_title: @fix.title, draft_name: @fix.name,
                                   draft_description: @fix.description, draft_body: @fix.body)
    end
    authorize @candidate
  end

  def create
    p = params.require(:skill_candidate).permit(:domain, :draft_title, :draft_description, :draft_body, :fix)
    @candidate = SkillCandidate.new(
      domain: p[:domain].to_s.strip.downcase.presence, draft_title: p[:draft_title], draft_description: p[:draft_description],
      draft_body: p[:draft_body].presence, origin: "manual", signature: "manual:#{SecureRandom.hex(8)}",
      requested_by: current_user, occurrence_count: 1, distinct_actor_count: 1,
      contributors: [{ "key" => "user:#{current_user.id}", "name" => current_user.name }],
      first_seen_at: Time.current, last_seen_at: Time.current
    )
    # "Fix this": publishing under the congested skill's name makes the next version, which registers the fix.
    @fix = Skill.current(p[:fix].to_s)
    @candidate.draft_name = @fix ? @fix.name : Capture::Naming.skill_name(@candidate.draft_title)
    @candidate.assign_attributes(status: "drafted", draft_generator: "human", drafted_at: Time.current) if @candidate.draft_body
    authorize @candidate
    if @candidate.draft_title.present? && @candidate.save
      AuditLog.record("skill_candidate.requested", user: current_user, subject: @candidate)
      @candidate.notify_reviewers!("Skill requested by #{current_user.name}: #{@candidate.display_title}")
      redirect_to @candidate, notice: "Request submitted for review."
    else
      @candidate.errors.add(:draft_title, "can't be blank") if @candidate.draft_title.blank?
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    attrs = params.require(:skill_candidate).permit(:draft_name, :draft_title, :draft_description, :draft_body,
                                                    :draft_tags, :draft_inputs, :draft_outputs, :review_notes).to_h
    attrs["draft_tags"] = attrs["draft_tags"].to_s.split(/[,\n]/).map { |t| t.strip.parameterize }.reject(&:blank?).uniq if attrs.key?("draft_tags")
    %w[draft_inputs draft_outputs].each { |k| attrs[k] = attrs[k].to_s.lines.map(&:strip).reject(&:blank?) if attrs.key?(k) }
    if attrs["draft_body"].present? && @candidate.status == "detected"
      attrs.merge!("status" => "drafted", "draft_generator" => "human", "drafted_at" => Time.current)
    end
    if @candidate.update(attrs)
      AuditLog.record("skill_candidate.edited", user: current_user, subject: @candidate)
      redirect_to @candidate, notice: "Draft saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def generate_draft
    Capture::DraftGenerator.call(@candidate)
    redirect_to @candidate, notice: "Draft generated (#{@candidate.draft_generator})."
  end

  def approve
    skill = Capture::Publisher.publish!(@candidate, reviewer: current_user)
    redirect_to skill, notice: "Published #{skill.name} v#{skill.version}."
  rescue Capture::Publisher::Error, ActiveRecord::RecordInvalid => e
    redirect_to @candidate, alert: e.message
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
    AuditLog.record("skill_candidate.#{status}", user: current_user, subject: @candidate, notes: @candidate.review_notes)
    redirect_to skill_candidates_path, notice: "Candidate #{status}."
  end
end
