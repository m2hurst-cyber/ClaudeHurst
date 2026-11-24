module Api
  module V1
    # Agents report each run of a skill: POST /api/v1/skills/:skill_id/runs
    #   { "model": "...", "input_tokens": 1200, "output_tokens": 800, "duration_ms": 42000, "status": "succeeded" }
    class SkillRunsController < BaseController
      def create
        skill = Skill.current(params[:skill_id]) or raise ActiveRecord::RecordNotFound
        run = SkillRun.from_report(skill, params.permit(:model, :input_tokens, :output_tokens, :duration_ms, :started_at, :finished_at, :status, :version, :trial_of, :engine, :nature),
                                   agent: params[:agent].to_s.strip.presence || current_source.name, source: current_source)
        run.engine = params[:engine].to_s.presence_in(%w[ai macro person]) || "ai"
        run.nature = params[:nature].to_s.presence_in(Capture::TaskProfile::NATURES.keys) || Capture::TaskProfile.infer([skill.title, skill.description].join(". "))
        run.cost = Capture::Models.cost(run.model, run.input_tokens, run.output_tokens)
        if run.engine == "macro" && (mr = Capture::MacroScreen.approved_for_skill(skill.name))
          mr.record_saving!(Capture::Estimator.for_step({ "title" => skill.title, "skill_name" => skill.name, "engine" => "ai" })["tokens"])
        end
        if run.save
          review = hand_over_macro(skill, run)
          render json: { id: run.id, usage: Capture::Intensity.for(skill.name),
                         macro_review: review && { id: review.id, status: review.status, url: macro_review_url(review) } }, status: :created
        else
          render json: { error: run.errors.full_messages.to_sentence }, status: :unprocessable_entity
        end
      end

      private

      # An agent that has just done the work can hand over the script that would do it again; if it
      # doesn't, and the task looks scriptable, the AI is asked to write one from this run.
      def hand_over_macro(skill, run)
        return nil unless run.engine == "ai" && run.status == "succeeded"
        key = skill.name
        existing = MacroReview.for_subject("skill", key)
        return existing if existing&.approved? || existing&.status == "rejected"
        m = params[:macro]
        if m.present? && m[:code].to_s.strip.length > 20
          r = existing || Capture::MacroScreen.review!(kind: "skill", key: key, title: skill.title, instructions: skill.description, skill: skill)
          r.update!(suggestion: r.suggestion.merge("language" => m[:language].to_s.presence_in(MacroReview::LANGUAGES) || "addin_js",
                                                   "code" => m[:code].to_s, "steps" => Array(m[:steps]).map(&:to_s).first(12),
                                                   "confidence" => m[:confidence].to_s.presence || "medium"),
                    written_by: "ai", source_run_id: run.id, status: "proposed",
                    reason: "#{r.reason} #{current_source.name} wrote this script from the run it just finished; approve it and later runs skip the AI.")
          r.notify_reviewers!
          AuditLog.record("macro_review.written_by_ai", source: current_source, subject: r, key: key)
          return r
        end
        MacroDraftJob.perform_later("skill", key, skill.title, app: SkillClassification.for(key)&.apps&.first || "Excel",
                                    instructions: skill.description, skill_name: key, note: params[:note].to_s.presence, usage: { "input_tokens" => run.input_tokens, "output_tokens" => run.output_tokens }, run_id: run.id)
        existing
      end
    end
  end
end
