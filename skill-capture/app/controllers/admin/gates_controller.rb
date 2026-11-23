module Admin
  class GatesController < BaseController
    def show = @policy = PromotionPolicy.current

    def update
      @policy = PromotionPolicy.current
      if @policy.update(params.require(:promotion_policy).permit(:initial_stage, :firm_min_trips, :firm_min_people, :firm_min_score,
                                                                  :market_min_days, :market_min_score, :market_max_tier, :market_requires_directions))
        AuditLog.record("gates.updated", user: current_user, policy: @policy.attributes.except("id", "created_at", "updated_at"))
        redirect_to admin_gates_path, notice: "Gates saved."
      else
        render :show, status: :unprocessable_entity
      end
    end
  end
end
