import { Controller } from "@hotwired/stimulus"

// One menu in the top bar: click (or Enter) opens it, Escape or a click anywhere else closes it, and
// opening one closes the others. Arrow keys walk the items.
export default class extends Controller {
  static targets = ["button", "panel"]

  connect() {
    this.away = (e) => { if (!this.element.contains(e.target)) this.close() }
    this.keys = (e) => { if (e.key === "Escape") { this.close(); this.buttonTarget.focus() } }
    document.addEventListener("click", this.away)
    document.addEventListener("keydown", this.keys)
  }
  disconnect() { document.removeEventListener("click", this.away); document.removeEventListener("keydown", this.keys) }

  toggle(e) {
    e.preventDefault(); e.stopPropagation()
    this.panelTarget.hidden ? this.open() : this.close()
  }

  open() {
    document.querySelectorAll("[data-controller~=nav-menu]").forEach((el) => {
      if (el !== this.element) el.dispatchEvent(new CustomEvent("nav-menu:close"))
    })
    this.panelTarget.hidden = false
    this.buttonTarget.setAttribute("aria-expanded", "true")
  }

  close() {
    if (!this.hasPanelTarget) return
    this.panelTarget.hidden = true
    this.buttonTarget.setAttribute("aria-expanded", "false")
  }

  // Arrow keys move between the items once the menu is open.
  nav(e) {
    if (!["ArrowDown", "ArrowUp"].includes(e.key)) return
    e.preventDefault()
    if (this.panelTarget.hidden) this.open()
    const items = [...this.panelTarget.querySelectorAll("a")]
    const i = items.indexOf(document.activeElement)
    items[(i + (e.key === "ArrowDown" ? 1 : items.length - 1) + (i < 0 ? 1 : 0)) % items.length]?.focus()
  }
}
