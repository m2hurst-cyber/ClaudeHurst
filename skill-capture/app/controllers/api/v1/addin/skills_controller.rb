module Api
  module V1
    module Addin
      class SkillsController < BaseController
        def index
          scope = Skill.published.visible_to(current_user).search(params[:q]).recent
          scope = scope.where(domain: params[:domain]) if params[:domain].present?
          render json: scope.limit(100).map { |s| summary(s) }
        end

        def show
          skill = Skill.current(params[:id])
          raise ActiveRecord::RecordNotFound unless skill&.visible_to?(current_user)
          next_up = SkillLink.neighbours(skill.name, direction: :next).filter_map do |l|
            (s = Skill.current(l[:name])) && s.visible_to?(current_user) && { name: s.name, title: s.title, traffic: l[:traffic] }
          end
          render json: summary(skill).merge(body: skill.body, url: skill_url(skill), contributors: Array(skill.source["contributors"]),
                                            next_up: next_up.first(3), traffic: traffic(skill.name),
                                            directions: place("road:#{skill.name}"), junction: next_up.any? ? place("junction:#{skill.name}") : nil,
                                            fix_url: new_skill_candidate_url(fix: skill.name),
                                            votes: SkillVote.tallies([skill.name])[skill.name],
                                            my_vote: SkillVote.find_by(user: current_user, skill_name: skill.name)&.value,
                                            can_vote: !Capture::Voting.own?(current_user, skill))
        end

        # PUT /api/v1/addin/skills/:name/vote  { value: 1 | -1 | 0, comment? }
        def vote
          skill = Skill.current(params[:id])
          raise ActiveRecord::RecordNotFound unless skill&.visible_to?(current_user)
          Capture::Voting.cast!(current_user, skill, params[:value], comment: params[:comment])
          render json: { votes: SkillVote.tallies([skill.name])[skill.name], my_vote: SkillVote.find_by(user: current_user, skill_name: skill.name)&.value }
        rescue Capture::Voting::Error => e
          render json: { error: e.message }, status: :forbidden
        end

        private

        def summary(s) = s.slice(:name, :version, :title, :description, :domain, :tags, :published_at, :stage)

        def place(key)
          pl = Capture::Directions.find(key, viewer: current_user)
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
