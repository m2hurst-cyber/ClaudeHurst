module Admin
  class ActionDefinitionsController < BaseController
    def index
      known = ActionDefinition.pluck(:key)
      ActionDefinition.insert_all(
        (UsageEvent.distinct.pluck(:action_key) - known).map { |k| { key: k, label: ActionDefinition.humanize_key(k), created_at: Time.current, updated_at: Time.current } }
      ) if UsageEvent.exists?
      @pagy, @definitions = pagy(ActionDefinition.order(:key), limit: 50)
    end

    def edit = @definition = ActionDefinition.find(params[:id])

    def update
      @definition = ActionDefinition.find(params[:id])
      if @definition.update(params.require(:action_definition).permit(:label, :domain).tap { |p| p[:domain] = p[:domain].to_s.strip.downcase.presence })
        redirect_to admin_action_definitions_path, notice: "Saved."
      else
        render :edit, status: :unprocessable_entity
      end
    end
  end
end
