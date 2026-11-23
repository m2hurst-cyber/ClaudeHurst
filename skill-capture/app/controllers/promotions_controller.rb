class PromotionsController < ApplicationController
  before_action :set_promotion, only: %i[approve reject withdraw]

  def index
    visible = Skill.published.visible_to(current_user).pluck(:name)
    @open = Promotion.open.where(skill_name: visible).recent.includes(:requested_by).to_a
    @decided = Promotion.where.not(status: "open").where(skill_name: visible).recent.limit(20).includes(:decided_by, :requested_by)
    @policy = PromotionPolicy.current
  end

  def create
    skill = Skill.find(params[:skill_id])
    authorize skill, :show?
    promotion = Capture::Promotions.new(current_user).request!(skill, pitch: params[:pitch], replaces: params[:replaces])
    redirect_to promotions_path(anchor: "promotion-#{promotion.id}"), notice: "Promotion to #{Skill::STAGE_LABELS[promotion.to_stage]} requested."
  rescue Capture::Promotions::Error => e
    redirect_back fallback_location: skill_path(skill), alert: e.message
  end

  def approve
    Capture::Promotions.new(current_user).approve!(@promotion, notes: params[:notes], waive: params[:waive] == "1")
    redirect_to promotions_path, notice: "Promoted “#{@promotion.skill&.title}” to #{Skill::STAGE_LABELS[@promotion.to_stage]}."
  rescue Capture::Promotions::Error => e
    redirect_to promotions_path, alert: e.message
  end

  def reject
    Capture::Promotions.new(current_user).reject!(@promotion, notes: params[:notes])
    redirect_to promotions_path, notice: "Request declined."
  rescue Capture::Promotions::Error => e
    redirect_to promotions_path, alert: e.message
  end

  def withdraw
    Capture::Promotions.new(current_user).withdraw!(@promotion)
    redirect_to promotions_path, notice: "Request withdrawn."
  rescue Capture::Promotions::Error => e
    redirect_to promotions_path, alert: e.message
  end

  private

  def set_promotion = @promotion = Promotion.find(params[:id])
end
