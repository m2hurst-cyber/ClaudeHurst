module Capture
  # Permissions and lookups for the resource library (callable folders of files and links).
  module ResourceLibrary
    module_function

    # Anyone who can see a folder can add to it; changing or removing an item is for the person
    # who added it, reviewers of a restricted folder's areas, and admins.
    def can_manage?(user, resource)
      return false unless user
      user.admin? || resource.uploaded_by_id == user.id ||
        (resource.folder.audience == "restricted" && resource.folder.areas.any? { |a| user.reviews?(a) })
    end

    def can_create_folder?(user, audience) = user.present? && (audience == "firm" || user.admin? || user.reviewer?)

    # Resources attached to a skill that this viewer may see (nil viewer = agents).
    def for_skill(name, viewer)
      SkillResource.where(skill_name: name).includes(resource: { folder: :parent }).map(&:resource)
                   .select { |r| viewer == :system || r.visible_to?(viewer) }
    end

    def describe(r, download_url:)
      { key: r.key, name: r.name, kind: r.kind, folder: r.folder.path, filename: r.filename,
        content_type: r.content_type, byte_size: r.byte_size, version: r.version,
        url: r.kind == "link" ? r.url : download_url }.compact
    end
  end
end
