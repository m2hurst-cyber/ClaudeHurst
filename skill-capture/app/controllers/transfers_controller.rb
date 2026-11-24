# Person-to-person transfers: send one skill or a selection straight to a coworker, free or for credits,
# without promoting it to a higher level.
class TransfersController < ApplicationController
  before_action :set_transfer, only: %i[show accept decline cancel]

  def index
    SkillTransfer.where(status: "offered").where("expires_at <= ?", Time.current).update_all(status: "expired")
    @incoming = current_user.received_transfers.includes(:sender).recent.limit(100)
    @outgoing = current_user.sent_transfers.includes(:recipient).recent.limit(100)
    @ledger = current_user.credit_entries.where.not(skill_transfer_id: nil).order(created_at: :desc).limit(20)
  end

  def new
    @coworkers = coworkers
    @sendable = sendable_skills
    @selected = Array(params[:skills]).map(&:to_s)
    @recipient_id = params[:recipient_id]
  end

  def create
    recipient = User.find(params[:recipient_id])
    t = SkillTransfer.offer!(sender: current_user, recipient: recipient, names: params[:skills], price: params[:price].presence || 0,
                             message: params[:message], allow_forward: params[:allow_forward] == "1")
    redirect_to transfer_path(t), notice: "Sent #{t.label} to #{recipient.name}#{t.free? ? '' : " for #{t.price.to_s('F')} credits"}."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to new_transfer_path(skills: params[:skills], recipient_id: params[:recipient_id]), alert: e.record.errors.full_messages.to_sentence
  rescue ActiveRecord::RecordNotFound
    redirect_to new_transfer_path(skills: params[:skills]), alert: "Choose a coworker."
  end

  def show
    @skills = @transfer.items.to_h { |i| [i["name"], Skill.current(i["name"])] }
  end

  def accept = respond_with { @transfer.accept!(by: current_user) }
  def decline = respond_with { @transfer.decline!(by: current_user) }
  def cancel = respond_with { @transfer.cancel!(by: current_user) }

  private

  def respond_with
    yield
    msg = { "accepted" => "Added #{@transfer.label} to your library#{@transfer.free? ? '' : " (#{@transfer.price.to_s('F')} credits paid)"}.",
            "declined" => "Declined.", "cancelled" => "Withdrawn." }[@transfer.status]
    redirect_to transfer_path(@transfer), notice: msg
  rescue SkillTransfer::Error => e
    redirect_to transfer_path(@transfer), alert: e.message
  end

  def set_transfer
    @transfer = SkillTransfer.find(params[:id])
    raise Pundit::NotAuthorizedError unless @transfer.involves?(current_user) || current_user.admin?
  end

  def coworkers = User.where.not(id: current_user.id).order(:name).to_a

  def sendable_skills
    Skill.published.visible_to(current_user).order(:title).to_a
         .select { |s| SkillTransfer.sendable?(s, current_user) }
         .map { |s| [s, SkillTransfer.sellable?(s, current_user)] }
  end
end
