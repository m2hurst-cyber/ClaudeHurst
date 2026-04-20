class TasksController < ApplicationController
  before_action :set_task, only: %i[show edit update destroy]
  before_action :set_subject, only: %i[new create]

  def index
    scope = Task.kept.by_due
    scope = scope.where(assignee: current_user) if params[:mine] == "1"
    @pagy, @tasks = pagy(scope)
  end

  def show; end

  def new
    @task = Task.new(subject: @subject, assignee: current_user, priority: "normal")
  end

  def create
    @task = Task.new(task_params.merge(subject: @subject))
    if @task.save
      redirect_to(@subject || tasks_path, notice: "Task created.")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if params[:task] && params[:task][:complete] == "1"
      @task.complete!
      return redirect_to tasks_path, notice: "Task completed."
    end
    if @task.update(task_params)
      redirect_to tasks_path, notice: "Task updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @task.discard
    redirect_to tasks_path, notice: "Task archived."
  end

  private

  def set_task
    @task = Task.kept.find(params[:id])
  end

  def set_subject
    @subject = if params[:company_id]
                 Company.kept.find(params[:company_id])
               elsif params[:deal_id]
                 Deal.kept.find(params[:deal_id])
               elsif params[:product_id]
                 Product.kept.find(params[:product_id])
               end
  end

  def task_params
    params.require(:task).permit(:title, :description, :due_on, :priority, :assignee_id)
  end
end
