import { Controller } from "@hotwired/stimulus"

// Hover/focus readout for the skill map's stacked bars. Built with textContent only.
export default class extends Controller {
  static targets = ["tip"]

  show(event) {
    const d = event.currentTarget.dataset
    const tip = this.tipTarget
    tip.replaceChildren()
    const value = document.createElement("div")
    value.className = "font-semibold"
    value.textContent = `${d.value} of ${d.total}`
    const label = document.createElement("div")
    label.className = "text-slate-600"
    label.textContent = `${d.stage} · ${d.area}`
    tip.append(value, label)
    tip.hidden = false
    this.place(event)
  }

  move(event) { this.place(event) }

  hide() { this.tipTarget.hidden = true }

  place(event) {
    const tip = this.tipTarget
    let x, y
    if (event.clientX !== undefined && event.type !== "focus") {
      x = event.clientX + 12; y = event.clientY + 12
    } else {
      const r = event.currentTarget.getBoundingClientRect()
      x = r.left; y = r.bottom + 6
    }
    const maxX = window.innerWidth - tip.offsetWidth - 8
    tip.style.left = `${Math.max(8, Math.min(x, maxX))}px`
    tip.style.top = `${y}px`
  }
}
