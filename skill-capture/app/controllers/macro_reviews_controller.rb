# The macro-suitability layer: tasks screened for "could a script do this instead of the AI?", waiting
# for a person to approve, correct or reject the macro. Approved macros run in place of AI calls.
class MacroReviewsController < ApplicationController
  before_action :set_review, only: %i[show update screen copy share export]
  before_action :reviewer_only, only: %i[update screen screen_all share import]

  # Approved macros anyone can reuse: shared with the firm, or promoted to the market.
  def library
    @macros = MacroReview.shared.order(runs_saved: :desc, updated_at: :desc)
    @mine = MacroReview.approved.where(proposed_by: current_user).where.not(visibility: %w[firm market])
    @targets = target_options
    @can_review = can_review?
  end

  # Put an approved macro to work on another skill or flow task.
  def copy
    kind, key, title = params[:target].to_s.split("|", 3)
    raise Pundit::NotAuthorizedError unless @review.visible_to?(current_user) || can_review?
    copy = @review.copy_to!(kind: kind, key: key, title: title.presence || @review.title, user: current_user)
    redirect_to macro_review_path(copy), notice: "Copied. Check it fits this task, then approve it."
  rescue ArgumentError => e
    redirect_to macro_review_path(@review), alert: e.message
  end

  def share
    v = params[:visibility].to_s.presence_in(MacroReview::VISIBILITIES) or raise Pundit::NotAuthorizedError
    @review.update!(visibility: v)
    AuditLog.record("macro_review.shared", user: current_user, subject: @review, visibility: v)
    redirect_to macro_review_path(@review), notice: { "private" => "Kept to yourself.", "firm" => "Shared with the firm.", "market" => "Promoted to the market." }[v]
  end

  # One macro as a file another firm (or another install) can import.
  def export
    raise Pundit::NotAuthorizedError unless @review.visible_to?(current_user) || can_review?
    send_data JSON.pretty_generate(@review.as_package), type: "application/json",
              filename: "macro-#{@review.subject_key.parameterize}.json", disposition: "attachment"
  end

  def import
    pkg = JSON.parse(params[:package].to_s)
    r = MacroReview.from_package(pkg, user: current_user)
    redirect_to macro_review_path(r), notice: "Imported. It's waiting for review before it runs."
  rescue JSON::ParserError, ArgumentError, ActiveRecord::RecordInvalid => e
    redirect_to library_macro_reviews_path, alert: "Couldn't import that: #{e.message}"
  end

  def index
    @open = MacroReview.open.order(score: :desc, updated_at: :desc)
    @approved = MacroReview.approved.order(tokens_saved: :desc)
    @rejected = MacroReview.where(status: "rejected").order(updated_at: :desc).limit(20)
    @saved = { runs: MacroReview.sum(:runs_saved), tokens: MacroReview.sum(:tokens_saved) }
    @can_review = can_review?
  end

  def show
    @can_review = can_review?
    @targets = target_options
    @copies = @review.copies.includes(:proposed_by)
    respond_to do |f|
      f.html
      f.md { render_markdown(markdown(@review), "macro-#{@review.subject_key.parameterize}") }
    end
  end

  def update
    attrs = params.require(:macro_review).permit(:status, :review_notes, :language, :code, :verdict)
    sug = @review.suggestion.merge("language" => attrs[:language].presence || @review.language, "code" => attrs[:code].to_s)
    @review.assign_attributes(suggestion: sug, review_notes: attrs[:review_notes], verdict: attrs[:verdict].presence || @review.verdict)
    @review.assign_attributes(status: attrs[:status], reviewed_by: current_user, reviewed_at: Time.current) if MacroReview::STATUSES.include?(attrs[:status])
    if @review.save
      AuditLog.record("macro_review.#{@review.status}", user: current_user, subject: @review, key: @review.subject_key)
      redirect_to macro_review_path(@review), notice: { "approved" => "Approved: this task now runs as a macro, with no tokens.", "rejected" => "Rejected: it stays with the AI.", "needs_work" => "Sent back for work." }[@review.status] || "Saved."
    else
      redirect_to macro_review_path(@review), alert: @review.errors.full_messages.to_sentence
    end
  end

  # Screen (or re-screen) one subject.
  def screen
    Capture::MacroScreen.review!(kind: @review.subject_kind, key: @review.subject_key, title: @review.title, user: current_user)
    redirect_to macro_review_path(@review), notice: "Screened again."
  end

  # Screen everything that hasn't been looked at: every published skill and every task in your flows.
  def screen_all
    n = Capture::MacroSweep.call(user: current_user)
    redirect_to macro_reviews_path, notice: "Screened #{helpers.pluralize(n, 'task')}."
  end

  private

  def set_review = @review = MacroReview.find(params[:id])

  # Everywhere an approved macro could be put to work.
  def target_options
    skills = Skill.published.visible_to(current_user).order(:title).limit(200).map { |s| ["skill|#{s.name}|#{s.title}", "Skill: #{s.title}"] }
    tasks = Flow.where(user: current_user).flat_map { |f| f.steps.reject { |s| Flow.pause?(s) }.map { |s| ["flow_step|#{f.id}:#{s['id']}|#{s['title']}", "#{f.name} › #{s['title']}"] } }
    (tasks + skills).first(300)
  end
  def can_review? = current_user.admin? || current_user.reviewer?
  def reviewer_only = (raise Pundit::NotAuthorizedError unless can_review?)

  def markdown(r)
    ["# Macro review: #{r.title}", "", "#{r.verdict_label} · score #{r.score} · #{r.status}", "", r.reason, "",
     "**For:** #{Array(r.signals['for']).to_sentence.presence || '—'}", "", "**Against:** #{Array(r.signals['against']).to_sentence.presence || '—'}", "",
     "## #{r.language_label}", "", "```#{r.language == 'vba' ? 'vb' : 'js'}", r.code, "```"].join("\n")
  end
end
