module Api
  module V1
    module Addin
      # Build and edit flows from the add-in's flowchart.
      class FlowsController < BaseController
        def index
          render json: {
            flows: Flow.where(user: current_user).order(updated_at: :desc).limit(50).map { |f| summary(f) },
            templates: Flow::TEMPLATES.map { |k, t| { key: k, name: t[:name], description: t[:description], steps: t[:steps].size } },
            runs: FlowRun.where(status: "running").includes(:flow, :user).order(updated_at: :desc).limit(50)
                         .select { |r| r.user_id == current_user.id || r.doer?(user: current_user) }.map { |r| run_summary(r) }
          }
        end

        def show = render(json: summary(find))

        def create
          f = if params[:template].present?
                Flow.from_template(params[:template].to_s, user: current_user, agent: Source.active.find_by(kind: "integration"))
              else
                Flow.new(user: current_user, name: params[:name].presence || "New flow", steps: Flow.normalize_steps(params[:steps]))
              end
          f.save ? render(json: summary(f), status: :created) : render(json: { error: f.errors.full_messages.to_sentence }, status: :unprocessable_entity)
        rescue KeyError
          render json: { error: "Unknown template" }, status: :unprocessable_entity
        end

        def update
          f = find
          f.assign_attributes(name: params[:name].presence || f.name, steps: Flow.normalize_steps(params[:steps]))
          f.save ? render(json: summary(f)) : render(json: { error: f.errors.full_messages.to_sentence }, status: :unprocessable_entity)
        end

        # Who can do a task: me, coworkers, agent integrations.
        def agents
          render json: {
            agents: Source.active.where(kind: "integration").order(:name).map { |s| { assignee: "agent:#{s.id}", name: s.name } },
            people: User.where.not(id: current_user.id).order(:name).limit(200).map { |u| { assignee: "user:#{u.id}", name: u.name, department: u.department } }
          }
        end

        private

        def find
          f = Flow.find(params[:id])
          raise Pundit::NotAuthorizedError unless f.visible_to?(current_user)
          f
        end

        def summary(f)
          { id: f.id, name: f.name, description: f.description, url: flow_url(f),
            steps: f.steps.map { |s| s.merge("assignee_label" => Flow.assignee_label(s["assignee"], owner: f.user)) } }
        end

        def run_summary(r)
          { id: r.id, flow: r.flow.name, status: r.status, current_index: r.current_index, total: r.steps.size,
            current: r.current && r.current.slice("title", "app").merge("mine" => r.doer?(user: current_user)), url: flow_run_url(r) }
        end
      end
    end
  end
end
