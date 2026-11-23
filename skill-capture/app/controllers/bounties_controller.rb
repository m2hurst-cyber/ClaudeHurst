class BountiesController < ApplicationController
  before_action :set_bounty, only: %i[approve reject close]

  def index
    @schedule = PricingSchedule.current
    visible = Skill.published.visible_to(current_user).pluck(:name)
    @active = Bounty.active.where(skill_name: visible).order(pool: :desc).to_a
    @metrics = SkillMetric.where(name: @active.map(&:skill_name)).index_by(&:name)
    @skills = Skill.published.where(name: @active.map(&:skill_name)).index_by(&:name)
    @paid = Bounty.where(status: "paid").order(approved_at: :desc).limit(10).includes(:solver)
    @leaders = CreditEntry.group(:user_id).order(Arel.sql("SUM(amount) DESC")).limit(10).sum(:amount)
                          .map { |uid, amt| [User.find_by(id: uid), amt] }.select(&:first)
    @congested = SkillMetric.where(name: visible).where.not(tier: nil).order(congestion_index: :desc).limit(10)
  end

  def approve
    Capture::Bounties.new.approve!(@bounty, by: current_user, notes: params[:notes])
    redirect_to bounties_path, notice: "Paid #{@bounty.payout.to_s('F')} to #{@bounty.solver.name}."
  rescue Capture::Bounties::Error => e
    redirect_to bounties_path, alert: e.message
  end

  def reject
    Capture::Bounties.new.reject!(@bounty, by: current_user, notes: params[:notes].presence || "no reason given")
    redirect_to bounties_path, notice: "Fix not accepted; the bounty is open again."
  rescue Capture::Bounties::Error => e
    redirect_to bounties_path, alert: e.message
  end

  def close
    Capture::Bounties.new.close!(@bounty, by: current_user, notes: params[:notes].presence || "Closed by admin")
    redirect_to bounties_path, notice: "Bounty closed."
  rescue Capture::Bounties::Error => e
    redirect_to bounties_path, alert: e.message
  end

  private

  def set_bounty = @bounty = Bounty.find(params[:id])
end
