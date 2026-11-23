# A callable folder in the resource library, e.g. "legal/templates".
#   firm        everyone signed in, and agents
#   restricted  people whose areas are listed (and admins); never agents
class ResourceFolder < ApplicationRecord
  AUDIENCES = %w[firm restricted].freeze

  belongs_to :parent, class_name: "ResourceFolder", optional: true
  belongs_to :created_by, class_name: "User", optional: true
  has_many :children, -> { order(:name) }, class_name: "ResourceFolder", foreign_key: :parent_id, dependent: :restrict_with_error
  has_many :resources, -> { order(:name) }, foreign_key: :folder_id, dependent: :restrict_with_error

  validates :name, presence: true, length: { maximum: 80 }
  validates :path, uniqueness: true
  validates :audience, inclusion: { in: AUDIENCES }

  before_validation do
    self.slug = name.to_s.parameterize if slug.blank? || name_changed?
    self.areas = Array(areas).map { |a| a.to_s.strip.downcase }.reject(&:blank?).uniq
    self.path = [parent&.path, slug].compact.join("/")
  end

  # Restrictions are inherited: a folder is visible only if it and every parent are.
  def visible_to?(user)
    chain.all? do |f|
      f.audience == "firm" || (user && (user.admin? || (user.domains & f.areas).any?))
    end
  end

  def chain
    list = []
    node = self
    while node && list.size < 10
      list.unshift(node)
      node = node.parent
    end
    list
  end

  def label = chain.map(&:name).join(" / ")

  def self.visible_to(user) = includes(:parent).select { |f| f.visible_to?(user) }

  def self.tree
    all_folders = all.to_a
    by_parent = all_folders.group_by(&:parent_id)
    walk = lambda do |pid, depth|
      Array(by_parent[pid]).sort_by(&:name).flat_map { |f| [[f, depth]] + walk.(f.id, depth + 1) }
    end
    walk.(nil, 0)
  end
end
