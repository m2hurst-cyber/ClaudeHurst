# Curated, linear workflows (for example the individual income tax return), installed as skills.
class PlaybooksController < ApplicationController
  before_action :set_playbook, only: %i[show install]

  def index
    @playbooks = Capture::Playbook.all
    @runs = current_user.playbook_runs.order(updated_at: :desc).limit(20)
  end

  def show
    @status = @playbook.status
    @situations = Situation.for_playbook(@playbook.key).to_a
    @runs = current_user.playbook_runs.where(playbook_key: @playbook.key).order(updated_at: :desc).limit(20)
  end

  def install
    report = @playbook.install!(user: current_user)
    redirect_to playbook_path(@playbook.key),
                notice: "Installed #{@playbook.title}: #{report.created.size} created, #{report.updated.size} updated, #{report.unchanged.size} unchanged, #{report.resources} resource files, #{report.situations} situations."
  rescue Capture::Playbook::Error, Capture::Publisher::Error => e
    redirect_to playbook_path(@playbook.key), alert: e.message
  end

  private

  def set_playbook
    @playbook = Capture::Playbook.find(params[:id])
  rescue Capture::Playbook::Error
    raise ActiveRecord::RecordNotFound
  end
end
