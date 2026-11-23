module Api
  module V1
    # Read access for agents and routing engines.
    class SkillsController < BaseController
      def index
        scope = Skill.published.shared.search(params[:q]).recent
        scope = scope.where(stage: params[:stage]) if Skill::SHARED_STAGES.include?(params[:stage])
        scope = scope.where(domain: params[:domain]) if params[:domain].present?
        render json: scope.limit(500).map { |s| summary(s) }
      end

      # GET /api/v1/skills/:name — current published version, with SKILL.md
      def show
        skill = Skill.current(params[:id])
        raise ActiveRecord::RecordNotFound unless skill&.shared?
        render json: summary(skill).merge(body: skill.body, skill_md: skill.to_skill_md)
      end

      # GET /api/v1/market: skills promoted to market, with SKILL.md and road directions, for a
      # marketplace or partner catalog.
      def market
        render json: Skill.published.where(stage: "market").recent.map { |s|
          summary(s).merge(skill_md: s.to_skill_md,
                           directions: Capture::Directions.find("road:#{s.name}", viewer: nil).body)
        }
      end

      private

      def summary(s)
        m = SkillMetric.for(s.name)
        s.slice(:name, :version, :title, :description, :domain, :tags, :license, :published_at, :stage)
         .merge(traffic: m&.priced? ? { tier: m.tier, congestion_index: m.congestion_index, price: m.price.to_f,
                                        currency: PricingSchedule.current.currency, bounty_pool: Bounty.active_for(s.name)&.pool&.to_f } : nil)
      end
    end
  end
end
