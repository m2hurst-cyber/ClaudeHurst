# A node in the field taxonomy. Paths are slugs joined by "/", kept in sync on save.
class Field < ApplicationRecord
  belongs_to :parent, class_name: "Field", optional: true
  has_many :children, -> { order(:position, :name) }, class_name: "Field", foreign_key: :parent_id, dependent: :restrict_with_error
  has_many :classifications, class_name: "SkillClassification", dependent: :nullify

  validates :name, presence: true, length: { maximum: 60 }
  validates :path, uniqueness: true
  validate { errors.add(:parent, "can't be itself or below itself") if parent && (parent == self || parent.path.start_with?("#{path}/")) && persisted? }

  before_validation do
    self.slug = name.to_s.parameterize if slug.blank? || name_changed?
    self.keywords = Array(keywords).map { |k| k.to_s.strip.downcase }.reject(&:blank?).uniq
    self.path = [parent&.path, slug].compact.join("/")
  end
  after_save :repath_children, if: :saved_change_to_path?

  scope :roots, -> { where(parent_id: nil).order(:position, :name) }

  def ancestors_and_self
    chain = []
    node = self
    while node && chain.size < 10
      chain.unshift(node)
      node = node.parent
    end
    chain
  end

  def label = ancestors_and_self.map(&:name).join(" › ")
  def depth = path.count("/")
  def subtree_ids = Field.where("path = :p OR path LIKE :c", p: path, c: "#{Field.sanitize_sql_like(path)}/%").pluck(:id)

  # Depth-first list of [field, depth] for pickers and trees.
  def self.tree
    all_fields = includes(:children).order(:position, :name).to_a
    by_parent = all_fields.group_by(&:parent_id)
    walk = lambda do |parent_id, depth|
      Array(by_parent[parent_id]).sort_by { |f| [f.position, f.name] }.flat_map { |f| [[f, depth]] + walk.(f.id, depth + 1) }
    end
    walk.(nil, 0)
  end

  private

  def repath_children
    children.each { |c| c.save! } # recomputes path from the new parent path
  end
end
