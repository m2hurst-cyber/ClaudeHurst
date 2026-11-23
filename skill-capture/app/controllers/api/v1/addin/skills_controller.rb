module Api
  module V1
    module Addin
      class SkillsController < BaseController
        def index
          scope = Skill.published.search(params[:q]).recent
          scope = scope.where(domain: params[:domain]) if params[:domain].present?
          render json: scope.limit(100).map { |s| summary(s) }
        end

        def show
          skill = Skill.current(params[:id]) || raise(ActiveRecord::RecordNotFound)
          next_up = SkillLink.neighbours(skill.name, direction: :next).filter_map do |l|
            (s = Skill.current(l[:name])) && { name: s.name, title: s.title, traffic: l[:traffic] }
          end
          render json: summary(skill).merge(body: skill.body, url: skill_url(skill), contributors: Array(skill.source["contributors"]),
                                            next_up: next_up.first(3), traffic: traffic(skill.name),
                                            directions: place("road:#{skill.name}"), junction: next_up.any? ? place("junction:#{skill.name}") : nil,
                                            fix_url: new_skill_candidate_url(fix: skill.name))
        end

        private

        def summary(s) = s.slice(:name, :version, :title, :description, :domain, :tags, :published_at)

        def place(key)
          pl = Capture::Directions.find(key)
          { key: pl.key, title: pl.title, written: pl.written, markdown: pl.body }
        rescue Capture::Directions::NotFound
          nil
        end

        def traffic(name)
          m = SkillMetric.for(name)
          return nil unless m&.priced?
          sched = PricingSchedule.current
          b = Bounty.active_for(name)
          { tier: m.tier, label: sched.tier(m.tier)["label"], rank: sched.rank(m.tier), tiers: sched.tiers.size,
            price: m.price.to_f, currency: sched.currency, median_minutes: m.median_minutes, freeflow_minutes: m.freeflow_minutes,
            bounty: b && { status: b.status, pool: b.pool.to_f } }
        end
      end
    end
  end
end
