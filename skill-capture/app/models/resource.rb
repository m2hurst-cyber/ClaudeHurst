# A file (template, worksheet, deck) or a link, callable by key: resource:<folder path>/<slug>.
class Resource < ApplicationRecord
  KINDS = %w[file link].freeze
  MAX_BYTES = 15.megabytes

  belongs_to :folder, class_name: "ResourceFolder"
  belongs_to :uploaded_by, class_name: "User", optional: true
  has_many :skill_resources, dependent: :delete_all

  validates :name, presence: true, length: { maximum: 120 }
  validates :slug, uniqueness: { scope: :folder_id }
  validates :kind, inclusion: { in: KINDS }
  validates :url, presence: true, format: { with: %r{\Ahttps://}i, message: "must be an https:// link" }, if: -> { kind == "link" }
  validates :content, presence: true, if: -> { kind == "file" }
  validates :byte_size, numericality: { less_than_or_equal_to: MAX_BYTES }, allow_nil: true

  before_validation { self.slug = name.to_s.parameterize if slug.blank? || name_changed? }

  def key = "resource:#{folder.path}/#{slug}"
  def visible_to?(user) = folder.visible_to?(user)
  def agents_can_read? = folder.visible_to?(nil)

  def self.find_by_key(key)
    path = key.to_s.delete_prefix("resource:")
    folder_path, _, slug = path.rpartition("/")
    folder = ResourceFolder.find_by(path: folder_path)
    folder && folder.resources.find_by(slug: slug)
  end

  def attach_file(io, filename:, content_type:)
    data = io.read
    self.kind = "file"
    self.content = data
    self.filename = File.basename(filename.to_s)
    self.content_type = content_type.presence || "application/octet-stream"
    self.byte_size = data.bytesize
    self.checksum = Digest::SHA256.hexdigest(data)
  end

  def extension = File.extname(filename.to_s).delete(".").downcase.presence || (kind == "link" ? "link" : "file")
end
