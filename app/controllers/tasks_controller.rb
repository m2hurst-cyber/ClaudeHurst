class TasksController < ApplicationController
  before_action :set_task, only: %i[show edit update destroy]

  def index
    scope = Task.kept.by_due
    scope = scope.where(assignee: current_user) if params[:mine] == "1"
    @pagy, @tasks = pagy(scope)
  end

  def show; end

  def new
    @task = Task.new(assignee: current_user, priority: "normal")
  end

  def create
    @task = Task.new(task_params)
    if @task.save
      redirect_to tasks_path, notice: "Task created."
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

  def task_params
    params.require(:task).permit(:title, :description, :due_on, :priority, :assignee_id)
  end
end
