module Capture
  # One canonical form for everything we hash: keys sorted at every depth, string keys,
  # no whitespace. The same input gives the same bytes in any process, any Ruby version,
  # and (because it is plain JSON with sorted keys) in any other language that has to
  # check our work.
  module Canonical
    module_function

    def form(value)
      case value
      when Hash
        value.keys.map(&:to_s).sort.to_h { |k| [k, form(value[k].nil? ? value[k.to_sym] : value[k])] }
      when Array then value.map { |v| form(v) }
      when Time, DateTime then value.utc.iso8601
      when Date then value.iso8601
      when Symbol then value.to_s
      else value
      end
    end

    def json(value) = JSON.generate(form(value))
    def digest(value) = Digest::SHA256.hexdigest(json(value))

    # Hash of two hashes, for the Merkle tree. Prefixed so a leaf can never be
    # mistaken for an interior node.
    def node(left, right) = Digest::SHA256.hexdigest("\x01#{left}#{right}")
    def leaf(hex) = Digest::SHA256.hexdigest("\x00#{hex}")

    # Merkle root over an ordered list of hex digests. Odd nodes carry up unchanged.
    def merkle_root(hexes)
      level = hexes.map { |h| leaf(h) }
      return nil if level.empty?
      while level.size > 1
        level = level.each_slice(2).map { |l, r| r ? node(l, r) : l }
      end
      level.first
    end
  end
end
