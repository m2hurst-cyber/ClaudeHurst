module Api
  module V1
    # Read access for agents and routing engines.
    class SkillsController < BaseController
      def index
        scope = Skill.published.search(params[:q]).recent
        scope = scope.where(domain: params[:domain]) if params[:domain].present?
        render json: scope.limit(500).map { |s| summary(s) }
      end

      # GET /api/v1/skills/:name — current published version, with SKILL.md
      def show
        skill = Skill.current(params[:id]) || raise(ActiveRecord::RecordNotFound)
        render json: summary(skill).merge(body: skill.body, skill_md: skill.to_skill_md)
      end

      private

      def summary(s)
        m = SkillMetric.for(s.name)
        s.slice(:name, :version, :title, :description, :domain, :tags, :license, :published_at)
         .merge(traffic: m&.priced? ? { tier: m.tier, congestion_index: m.congestion_index, price: m.price.to_f,
                                        currency: PricingSchedule.current.currency, bounty_pool: Bounty.active_for(s.name)&.pool&.to_f } : nil)
      end
    end
  end
end
