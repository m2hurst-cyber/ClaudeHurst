module Api
  module V1
    module Addin
      # POST a worksheet's labels and formulas (never its numbers); get back what was observed, how it
      # was interpreted, the documented files and the drafted skill (Observe → Interpret → Document → Write).
      class WorksheetCapturesController < BaseController
        MAX_BODY = 2.megabytes

        def create
          return render(json: { error: "Sheet too large to capture" }, status: :payload_too_large) if request.content_length.to_i > MAX_BODY
          payload = params.permit(:sheet, :address, cells: %i[a f t n]).to_h
          capture = Capture::WorksheetInterpreter.call(user: current_user, payload: payload)
          render json: summary(capture), status: :created
        rescue Capture::WorksheetInterpreter::Error => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        def show
          capture = WorksheetCapture.find(params[:id])
          return render(json: { error: "not allowed" }, status: :forbidden) unless capture.visible_to?(current_user)
          render json: summary(capture)
        end

        private

        def summary(c)
          i = c.interpretation
          {
            id: c.id, sheet: c.sheet_name, provider: c.provider, provider_name: FormulaCommand.provider_name(c.provider),
            interpreted_by: c.interpreted_by,
            observed: c.observed["summary"],
            interpreted: { title: i["title"], purpose: i["purpose"], kind: i["kind"], field: i["field"], risks: i["risks"], dependencies: i["dependencies"] },
            documented: { formulas: c.inventory.size, commands: c.inventory.count { |e| e["kind"] == "command" },
                          new_commands: c.inventory.count { |e| e["status"].to_s.include?("new") }, files: c.files.keys },
            written: c.candidate && { name: c.candidate.draft_name, title: c.candidate.draft_title, candidate_url: skill_candidate_url(c.candidate) },
            url: worksheet_capture_url(c)
          }
        end
      end
    end
  end
end
