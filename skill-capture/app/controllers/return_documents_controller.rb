# Documents on a return: upload (read by the AI when enabled), check and confirm the figures,
# view, delete. Only the filer changes them; the assigned reviewer can view them.
class ReturnDocumentsController < ApplicationController
  before_action :set_run
  before_action :set_document, except: :create
  before_action :filer_only, except: :show

  def create
    files = Array(params[:files]).select { |f| f.respond_to?(:read) }
    return redirect_to(playbook_run_path(@run, anchor: "documents"), alert: "Choose one or more files") if files.empty?
    docs = Capture::ReturnDocuments.upload!(@run, files, user: current_user)
    note = Capture::DocumentReader.enabled? ? "The AI is reading #{docs.size == 1 ? 'it' : 'them'}; check the figures when they appear." : "Choose each one's kind and enter its boxes."
    redirect_to playbook_run_path(@run, anchor: "documents"), notice: "Uploaded #{docs.size} document(s). #{note}"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to playbook_run_path(@run, anchor: "documents"), alert: e.record.errors.full_messages.to_sentence
  end

  def show
    disposition = params[:download] ? "attachment" : "inline"
    AuditLog.record("return.document_viewed", user: current_user, subject: @run, document: @document.id)
    send_data @document.bytes, filename: @document.filename.presence || "document", type: @document.content_type, disposition: disposition
  end

  # PATCH kind, tax_year, payer, fields[...], confirm=1
  def update
    p = params.permit(:kind, :tax_year, :payer, fields: {}).to_h.symbolize_keys
    Capture::ReturnDocuments.update!(@document, p, user: current_user, confirm: params[:confirm] == "1")
    redirect_to playbook_run_path(@run, anchor: "doc-#{@document.id}"), notice: params[:confirm] == "1" ? "#{@document.label} confirmed." : "Saved."
  rescue ArgumentError => e
    redirect_to playbook_run_path(@run, anchor: "doc-#{@document.id}"), alert: e.message
  end

  def read
    raise ActiveRecord::RecordNotFound unless Capture::DocumentReader.enabled?
    @document.update!(status: "reading")
    ReturnDocumentReadJob.perform_later(@document.id)
    redirect_to playbook_run_path(@run, anchor: "doc-#{@document.id}"), notice: "Reading it again."
  end

  def destroy
    @document.destroy!
    AuditLog.record("return.document_deleted", user: current_user, subject: @run, document: @document.id)
    Capture::Legs.new(@run).verify_all!
    redirect_to playbook_run_path(@run, anchor: "documents"), notice: "Deleted."
  end

  private

  def set_run
    @run = PlaybookRun.find(params[:playbook_run_id])
    raise ActiveRecord::RecordNotFound unless @run.visible_to?(current_user)
  end

  def set_document = @document = @run.documents.find(params[:id])
  def filer_only = (raise Pundit::NotAuthorizedError unless @run.user_id == current_user.id)
end
