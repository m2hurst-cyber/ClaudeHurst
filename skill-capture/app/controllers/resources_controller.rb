# The resource library: callable folders of templates, worksheets, decks and links.
class ResourcesController < ApplicationController
  before_action :set_resource, only: %i[show download update destroy]

  def index
    @folders = ResourceFolder.tree.select { |f, _| f.visible_to?(current_user) }
    @folder = ResourceFolder.find_by(path: params[:folder]) if params[:folder].present?
    @folder = nil if @folder && !@folder.visible_to?(current_user)
    visible_ids = @folders.map { |f, _| f.id }
    scope = Resource.includes(folder: :parent).where(folder_id: @folder ? [@folder.id] : visible_ids).order(:name)
    if params[:q].present?
      t = "%#{Resource.sanitize_sql_like(params[:q])}%"
      scope = scope.where("resources.name ILIKE :t OR resources.description ILIKE :t OR resources.filename ILIKE :t", t: t)
    end
    @resources = scope.to_a
    @usage = SkillResource.where(resource_id: @resources.map(&:id)).group(:resource_id).count
    @new_resource = Resource.new(folder: @folder)
  end

  def show
    @skills = Skill.published.where(name: @resource.skill_resources.select(:skill_name)).select { |s| s.visible_to?(current_user) }
  end

  def download
    return redirect_to(@resource.url, allow_other_host: true) if @resource.kind == "link"
    send_data @resource.content, filename: @resource.filename, type: @resource.content_type, disposition: "attachment"
  end

  def create
    folder = ResourceFolder.find(params.dig(:resource, :folder_id))
    raise Pundit::NotAuthorizedError unless folder.visible_to?(current_user)
    r = folder.resources.new(params.require(:resource).permit(:name, :description, :url).merge(uploaded_by: current_user))
    if (file = params.dig(:resource, :file)).respond_to?(:read)
      r.attach_file(file, filename: file.original_filename, content_type: file.content_type)
      r.name = File.basename(file.original_filename, ".*").tr("_-", "  ").squish if r.name.blank?
    else
      r.kind = "link"
    end
    if r.save
      AuditLog.record("resource.created", user: current_user, subject: r, key: r.key)
      attach_to_skill(r)
      redirect_to resource_path(r), notice: "Added #{r.name} (#{r.key})."
    else
      redirect_back fallback_location: resources_path, alert: r.errors.full_messages.to_sentence
    end
  end

  # Replace the file (new version) or edit details.
  def update
    raise Pundit::NotAuthorizedError unless Capture::ResourceLibrary.can_manage?(current_user, @resource)
    @resource.assign_attributes(params.require(:resource).permit(:name, :description, :url))
    if (file = params.dig(:resource, :file)).respond_to?(:read)
      @resource.attach_file(file, filename: file.original_filename, content_type: file.content_type)
      @resource.version += 1
    end
    if @resource.save
      AuditLog.record("resource.updated", user: current_user, subject: @resource, version: @resource.version)
      redirect_to resource_path(@resource), notice: "Saved#{" as version #{@resource.version}" if @resource.version_previously_changed?}."
    else
      redirect_to resource_path(@resource), alert: @resource.errors.full_messages.to_sentence
    end
  end

  def destroy
    raise Pundit::NotAuthorizedError unless Capture::ResourceLibrary.can_manage?(current_user, @resource)
    @resource.destroy!
    AuditLog.record("resource.removed", user: current_user, key: @resource.key)
    redirect_to resources_path(folder: @resource.folder.path), notice: "Removed #{@resource.name}."
  end

  private

  def set_resource
    @resource = Resource.includes(folder: :parent).find(params[:id])
    raise Pundit::NotAuthorizedError unless @resource.visible_to?(current_user)
  end

  def attach_to_skill(resource)
    skill = params[:skill_id].present? && Skill.find_by(id: params[:skill_id])
    return unless skill && SkillPolicy.new(current_user, skill).classify?
    SkillResource.find_or_create_by!(skill_name: skill.name, resource: resource) { |sr| sr.added_by = current_user }
  end
end
