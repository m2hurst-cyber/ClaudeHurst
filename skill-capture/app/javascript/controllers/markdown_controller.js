import { Controller } from "@hotwired/stimulus"
import { renderMarkdown } from "addin/markdown"

// Renders the Markdown in data-markdown-source-value (escaped, safe subset) into this element.
export default class extends Controller {
  static values = { source: String }
  connect() { this.element.innerHTML = renderMarkdown(this.sourceValue) }
}
