import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "backdrop"]

  connect() {
    this.close()
  }

  open() {
    document.body.classList.add("overflow-hidden")
    this.backdropTarget.classList.remove("hidden")
    this.panelTarget.classList.remove("-translate-x-full")
    this.panelTarget.classList.add("translate-x-0")
  }

  close() {
    document.body.classList.remove("overflow-hidden")
    if (this.hasBackdropTarget) this.backdropTarget.classList.add("hidden")
    if (this.hasPanelTarget) {
      this.panelTarget.classList.add("-translate-x-full")
      this.panelTarget.classList.remove("translate-x-0")
    }
  }
}
