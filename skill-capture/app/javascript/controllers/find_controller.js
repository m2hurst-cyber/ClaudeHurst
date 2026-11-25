import { Controller } from "@hotwired/stimulus"

// "/" focuses the ask box from anywhere on the page; Escape gives the page back.
export default class extends Controller {
  static targets = ["box"]

  connect() {
    this.key = (e) => {
      const typing = /^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement?.tagName) || document.activeElement?.isContentEditable
      if (e.key === "/" && !typing) { e.preventDefault(); this.boxTarget.focus(); this.boxTarget.select() }
      if (e.key === "Escape" && document.activeElement === this.boxTarget) this.boxTarget.blur()
    }
    document.addEventListener("keydown", this.key)
  }
  disconnect() { document.removeEventListener("keydown", this.key) }
}
