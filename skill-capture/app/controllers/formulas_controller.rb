require "csv"

# The provider formula libraries (BQL, FactSet): browse, search, add, import, and verify the
# commands worksheet skills are built from. Area reviewers for the provider and admins manage them.
class FormulasController < ApplicationController
  before_action :set_provider
  before_action :manager_only, except: %i[index guide]

  def index
    scope = FormulaCommand.where(provider: @provider)
    @counts = scope.group(:status).count
    @categories = scope.group(:category).order(:category).count
    scope = scope.where(category: params[:category]) if params[:category].present?
    scope = scope.where(status: params[:status]) if FormulaCommand::STATUSES.include?(params[:status])
    if params[:q].present?
      t = "%#{FormulaCommand.sanitize_sql_like(params[:q])}%"
      scope = scope.where("key ILIKE :t OR name ILIKE :t OR syntax ILIKE :t OR description ILIKE :t", t: t)
    end
    @commands = scope.order(:category, :name).to_a
    return render_markdown(Capture::LlmMarkdown.formulas(@provider, @commands), "#{@provider}-formulas") if request.format.md?
    @usage = Skill.published.where(domain: @provider).where("skills.source -> 'worksheet' IS NOT NULL").each_with_object(Hash.new { |h, k| h[k] = [] }) do |s, h|
      Capture::Worksheets.command_keys(s.source["worksheet"]).each { |k| h[k] << s }
    end
    @can_manage = can_manage?
    @providers = (FormulaCommand::PROVIDERS.keys | FormulaCommand.distinct.pluck(:provider))
  end

  # The provider's agent guide (playbooks/<pack>/AGENT.md): how to read a worksheet and write its skill.
  def guide
    @guide = Capture::Playbook.all.find { |pb| pb.pack? && pb.provider == @provider }&.guide
    raise ActiveRecord::RecordNotFound unless @guide
    render_markdown(@guide, "#{@provider}-AGENT") if request.format.md?
  end

  def create
    cmd = FormulaCommand.new(command_params.merge(provider: @provider, origin: "console", created_by: current_user, status: "unverified"))
    if cmd.save
      AuditLog.record("formula.created", user: current_user, subject: cmd, provider: @provider, key: cmd.key)
      redirect_to formulas_path(provider: @provider, q: cmd.key), notice: "Added #{cmd.name}."
    else
      redirect_to formulas_path(provider: @provider), alert: cmd.errors.full_messages.to_sentence
    end
  end

  # PATCH: edit, or status=verified|unverified|deprecated with a note
  def update
    cmd = FormulaCommand.find_by!(provider: @provider, id: params[:id])
    if params[:status]
      raise ActiveRecord::RecordInvalid unless FormulaCommand::STATUSES.include?(params[:status])
      cmd.update!(status: params[:status], verification_note: params[:note].to_s.squish.first(500).presence,
                  verified_by: params[:status] == "verified" ? current_user : nil, verified_at: params[:status] == "verified" ? Time.current : nil)
      AuditLog.record("formula.#{params[:status]}", user: current_user, subject: cmd, key: cmd.key)
      return redirect_to(formulas_path(provider: @provider, q: params[:q], category: params[:category], anchor: "cmd-#{cmd.id}"), notice: "#{cmd.name}: #{params[:status]}.")
    end
    syntax_changed = command_params[:syntax].present? && command_params[:syntax] != cmd.syntax
    cmd.assign_attributes(command_params)
    cmd.assign_attributes(status: "unverified", verified_by: nil, verified_at: nil) if syntax_changed
    if cmd.save
      AuditLog.record("formula.updated", user: current_user, subject: cmd, key: cmd.key, syntax_changed: syntax_changed)
      redirect_to formulas_path(provider: @provider, anchor: "cmd-#{cmd.id}"), notice: "Saved#{' (back to unverified: the formula changed)' if syntax_changed}."
    else
      redirect_to formulas_path(provider: @provider), alert: cmd.errors.full_messages.to_sentence
    end
  end

  # POST file: CSV with key,name,category,syntax,description,defaults ("fpt=A; fpo=0")
  def import
    file = params[:file]
    return redirect_to(formulas_path(provider: @provider), alert: "Choose a CSV file") unless file.respond_to?(:read)
    made = updated = 0
    errors = []
    CSV.parse(file.read.force_encoding("UTF-8").delete_prefix("﻿"), headers: true).each_with_index do |row, i|
      h = row.to_h.transform_keys { |k| k.to_s.strip.downcase }
      cmd = FormulaCommand.find_or_initialize_by(provider: @provider, key: h["key"].to_s.strip)
      defaults = h["defaults"].to_s.split(/[;|]/).filter_map { |kv| k, v = kv.split("=", 2).map(&:strip); [k, v] if k.present? }.to_h
      was_new = cmd.new_record?
      cmd.assign_attributes(name: h["name"].presence || cmd.name || h["key"], category: h["category"].presence || cmd.category || "Other",
                            syntax: h["syntax"].presence || cmd.syntax, description: h["description"].presence || cmd.description,
                            defaults: defaults.presence || cmd.defaults || {}, origin: was_new ? "import" : cmd.origin, created_by: cmd.created_by || current_user)
      cmd.assign_attributes(status: "unverified", verified_by: nil, verified_at: nil) if cmd.syntax_changed? && !was_new
      if cmd.save then was_new ? made += 1 : (cmd.previous_changes.any? ? updated += 1 : nil)
      else errors << "row #{i + 2} (#{h['key']}): #{cmd.errors.full_messages.to_sentence}"
      end
    end
    AuditLog.record("formula.imported", user: current_user, provider: @provider, created: made, updated: updated, errors: errors.size)
    msg = "Imported: #{made} new, #{updated} updated."
    errors.any? ? redirect_to(formulas_path(provider: @provider), alert: "#{msg} #{errors.size} skipped: #{errors.first(3).join('; ')}") : redirect_to(formulas_path(provider: @provider), notice: msg)
  rescue CSV::MalformedCSVError => e
    redirect_to formulas_path(provider: @provider), alert: "That file isn't valid CSV: #{e.message}"
  end

  private

  def set_provider = @provider = params[:provider].presence_in(FormulaCommand::PROVIDERS.keys | FormulaCommand.distinct.pluck(:provider)) || "bql"
  def can_manage? = current_user.admin? || current_user.reviews?(@provider)
  def manager_only = (raise Pundit::NotAuthorizedError unless can_manage?)
  def command_params = params.fetch(:formula_command, {}).permit(:key, :name, :category, :syntax, :description).to_h.symbolize_keys
end
