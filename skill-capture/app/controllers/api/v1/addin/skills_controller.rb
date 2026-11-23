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
          render json: summary(skill).merge(body: skill.body, url: skill_url(skill), contributors: Array(skill.source["contributors"]))
        end

        private

        def summary(s) = s.slice(:name, :version, :title, :description, :domain, :tags, :published_at)
      end
    end
  end
end
