# A tax document uploaded to a return (a W-2, a 1099, the prepared 1040, a payment confirmation).
# The file, its name, the payer and the figures read from it are encrypted at rest. Identifiers
# (SSNs, EINs, account numbers) are never stored as figures: see Capture::DocumentReader.
class ReturnDocument < ApplicationRecord
  STATUSES = %w[uploaded reading read confirmed failed].freeze
  TYPES = { "application/pdf" => "PDF", "image/png" => "PNG", "image/jpeg" => "JPG", "image/webp" => "WEBP", "image/gif" => "GIF" }.freeze
  MAX_BYTES = 15.megabytes
  IDENTIFIER = /\b\d{3}-\d{2}-\d{4}\b|\b\d{2}-\d{7}\b|\b\d{9}\b|\b\d{10,}\b/ # SSN/ITIN, EIN, long account numbers

  encrypts :content, :filename, :payer, :fields_json

  belongs_to :playbook_run
  belongs_to :uploaded_by, class_name: "User", optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :content_type, inclusion: { in: TYPES.keys, message: "must be a PDF or an image (PNG, JPG, WEBP, GIF)" }
  validates :byte_size, numericality: { greater_than: 0, less_than_or_equal_to: MAX_BYTES }
  validates :checksum, uniqueness: { scope: :playbook_run_id, message: "matches a document already on this return" }

  scope :confirmed, -> { where(status: "confirmed") }
  scope :ordered, -> { order(:kind, :id) }

  def self.from_upload(run, file, user:)
    data = file.read
    new(playbook_run: run, filename: File.basename(file.original_filename.to_s).first(200), content_type: file.content_type.to_s,
        byte_size: data.bytesize, checksum: Digest::SHA256.hexdigest(data), content: Base64.strict_encode64(data), uploaded_by: user)
  end

  def bytes = Base64.decode64(content)
  def fields = fields_json.present? ? JSON.parse(fields_json) : {}

  # Keeps only the catalog's fields for this kind, typed; drops anything that looks like an identifier.
  def assign_fields(raw, catalog)
    spec = catalog.dig(kind, "fields") || []
    self.fields_json = spec.each_with_object({}) do |f, h|
      v = raw.respond_to?(:key?) ? (raw[f["key"]] || raw[f["key"].to_sym]) : nil
      next if v.nil? || v.to_s.strip.empty?
      h[f["key"]] = cast(v, f["type"])
    end.compact.to_json
  end

  def kind_name(catalog) = catalog.dig(kind, "name") || "Unidentified document"
  def pending? = %w[uploaded reading].include?(status)

  private

  def cast(v, type)
    s = v.to_s.strip
    case type
    when "money", "number"
      n = s.delete(",$ ").then { |x| x.match?(/\A-?\(?\d+(\.\d+)?\)?\z/) ? x : nil }
      n && (n.start_with?("(") ? -n.delete("()").to_f : n.to_f).round(2)
    when "yes_no" then %w[yes true 1 y x].include?(s.downcase) ? "yes" : (%w[no false 0 n].include?(s.downcase) ? "no" : nil)
    when "date" then (Date.parse(s).iso8601 rescue nil)
    else s.gsub(IDENTIFIER, "").squish.first(80).presence
    end
  end
end
