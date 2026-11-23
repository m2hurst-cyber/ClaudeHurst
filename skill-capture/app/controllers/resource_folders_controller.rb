class ResourceFoldersController < ApplicationController
  def create
    p = params.require(:resource_folder).permit(:name, :parent_id, :audience, :areas, :description)
    parent = p[:parent_id].present? ? ResourceFolder.find(p[:parent_id]) : nil
    raise Pundit::NotAuthorizedError if parent && !parent.visible_to?(current_user)
    raise Pundit::NotAuthorizedError unless Capture::ResourceLibrary.can_create_folder?(current_user, p[:audience])
    folder = ResourceFolder.new(name: p[:name], parent: parent, audience: p[:audience].presence || "firm",
                                areas: p[:areas].to_s.split(","), description: p[:description], created_by: current_user)
    if folder.save
      AuditLog.record("resource_folder.created", user: current_user, subject: folder, path: folder.path)
      redirect_to resources_path(folder: folder.path), notice: "Folder #{folder.label} created."
    else
      redirect_back fallback_location: resources_path, alert: folder.errors.full_messages.to_sentence
    end
  end
end
