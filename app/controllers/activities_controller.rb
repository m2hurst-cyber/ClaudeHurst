class ActivitiesController < ApplicationController
  before_action :set_subject, only: %i[new create index]
  before_action :set_activity, only: %i[show edit update destroy]

  def index
    @activities = @subject.activities.recent
  end

  def show; end

  def new
    @activity = @subject.activities.new(user: current_user, occurred_at: Time.current, kind: "note")
  end

  def create
    @activity = @subject.activities.new(activity_params.merge(user: current_user))
    @activity.occurred_at ||= Time.current
    if @activity.save
      redirect_to @subject, notice: "Activity logged."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @activity.update(activity_params)
      redirect_to @activity.subject, notice: "Activity updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    subj = @activity.subject
    @activity.destroy
    redirect_to subj, notice: "Activity removed."
  end

  private

  def set_subject
    if params[:company_id]
      @subject = Company.kept.find_by!(slug: params[:company_id])
    elsif params[:deal_id]
      @subject = Deal.kept.find(params[:deal_id])
    end
  end

  def set_activity
    @activity = Activity.find(params[:id])
  end

  def activity_params
    params.require(:activity).permit(:kind, :occurred_at, :body, :duration_minutes)
  end
end
