# Worksheets captured from Excel: each one's four stages (observed, interpreted, documented, written)
# and its files. People see their own captures; reviewers see the ones waiting on them; admins see all.
class WorksheetCapturesController < ApplicationController
  before_action :set_capture, only: %i[show file]

  def index
    scope = WorksheetCapture.includes(:user, :candidate).order(created_at: :desc)
    scope = scope.where(user: current_user) unless current_user.admin?
    reviewing = WorksheetCapture.includes(:user, :candidate).where.not(user: current_user).where.not(candidate_id: nil).order(created_at: :desc).limit(200)
                                .select { |c| c.candidate.open? && c.candidate.reviewable_by?(current_user) }
    @captures = (scope.limit(100).to_a | reviewing)
  end

  def show
    return render_markdown(Capture::LlmMarkdown.capture(@capture), "capture-#{@capture.sheet_name}") if request.format.md?
  end

  def file
    body = @capture.files[params[:file]] or raise ActiveRecord::RecordNotFound
    send_data body, filename: params[:file], type: params[:file].end_with?(".json") ? "application/json" : "text/markdown", disposition: params[:download] ? "attachment" : "inline"
  end

  private

  def set_capture
    @capture = WorksheetCapture.find(params[:id])
    raise Pundit::NotAuthorizedError unless @capture.visible_to?(current_user)
  end
end
