# The model catalogue: tiers, prices and speed, used to anticipate a task's cost and to pick the model
# a task should run on. Admins edit the numbers to match their contract.
class ModelProfilesController < ApplicationController
  def index
    Capture::Models.ensure_defaults!
    @models = ModelProfile.order(:position, :key)
    @usage = SkillRun.where(occurred_at: Capture::Intensity::WINDOW.ago..).group(:model)
                     .pluck(:model, Arel.sql("COUNT(*)"), Arel.sql("SUM(input_tokens)"), Arel.sql("SUM(output_tokens)"), Arel.sql("SUM(cost)"))
                     .to_h { |m, n, i, o, c| [m, { runs: n, input: i.to_i, output: o.to_i, cost: c.to_d }] }
    @by_nature = SkillRun.where(occurred_at: Capture::Intensity::WINDOW.ago..).where.not(nature: nil)
                         .group(:nature, :model).pluck(:nature, :model, Arel.sql("COUNT(*)"), Arel.sql("AVG(input_tokens + output_tokens)"))
  end

  def update
    raise Pundit::NotAuthorizedError unless current_user.admin?
    m = ModelProfile.find(params[:id])
    m.update!(params.require(:model_profile).permit(:name, :tier, :input_cost, :output_cost, :tokens_per_second, :active, :notes))
    AuditLog.record("model_profile.updated", user: current_user, subject: m, key: m.key)
    redirect_to model_profiles_path, notice: "Saved #{m.name}."
  end
end
