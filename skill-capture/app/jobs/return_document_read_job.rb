# Reads an uploaded return document with the AI, then re-verifies the return's legs.
class ReturnDocumentReadJob < ApplicationJob
  queue_as :default

  def perform(doc_id)
    doc = ReturnDocument.find_by(id: doc_id) or return
    Capture::ReturnDocuments.read!(doc)
  end
end
