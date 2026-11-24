module Api
  module V1
    module Addin
      # Send skills to a coworker from inside Office, and accept or decline what was sent to you.
      class TransfersController < BaseController
        def index
          render json: {
            credits: current_user.credits.to_s("F"),
            incoming: current_user.received_transfers.pending.includes(:sender).recent.limit(20).map { |t| summary(t) },
            outgoing: current_user.sent_transfers.includes(:recipient).recent.limit(10).map { |t| summary(t) }
          }
        end

        def coworkers
          scope = User.where.not(id: current_user.id).order(:name)
          scope = scope.where("name ILIKE ?", "%#{User.sanitize_sql_like(params[:q])}%") if params[:q].present?
          render json: scope.limit(50).map { |u| { id: u.id, name: u.name, department: u.department } }
        end

        def create
          skill = Skill.current(Array(params[:skills]).first.to_s)
          t = SkillTransfer.offer!(sender: current_user, recipient: User.find(params[:recipient_id]), names: params[:skills],
                                   price: params[:price].presence || 0, message: params[:message], allow_forward: params[:allow_forward] == true || params[:allow_forward] == "1")
          render json: summary(t).merge(sellable: skill && SkillTransfer.sellable?(skill, current_user)), status: :created
        rescue ActiveRecord::RecordInvalid => e
          render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
        end

        def accept = respond { |t| t.accept!(by: current_user) }
        def decline = respond { |t| t.decline!(by: current_user) }

        private

        def respond
          t = current_user.received_transfers.find(params[:id])
          yield t
          render json: summary(t).merge(credits: current_user.credits.to_s("F"))
        rescue SkillTransfer::Error => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        def summary(t)
          { id: t.id, label: t.label, status: t.pending? ? "offered" : (t.status == "offered" ? "expired" : t.status),
            price: t.price.to_s("F"), free: t.free?, message: t.message, from: t.sender.name, to: t.recipient.name,
            skills: t.items.map { |i| i.slice("name", "title", "version") }, url: transfer_url(t) }
        end
      end
    end
  end
end
