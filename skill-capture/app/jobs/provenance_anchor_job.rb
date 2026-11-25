# Daily: commit to yesterday's provenance entries, and say so loudly if the chain is broken.
class ProvenanceAnchorJob < ApplicationJob
  queue_as :default

  def perform(on = Date.current - 1)
    verdict = Capture::Provenance.verify
    Rails.logger.error("PROVENANCE CHAIN BROKEN: #{verdict}") unless verdict.ok
    anchor = Capture::Provenance.anchor!(on)
    Rails.logger.info(anchor ? "Provenance anchored #{on}: #{anchor.entry_count} entries, root #{anchor.root_hash.first(12)}" : "Provenance: nothing to anchor for #{on}")
    anchor
  end
end
