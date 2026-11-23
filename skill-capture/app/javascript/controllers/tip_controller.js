import { Controller } from "@hotwired/stimulus"

// Generic hover/focus tooltip. Marks carry data-tip="line 1\nline 2"; the first line is emphasized.
export default class extends Controller {
  static targets = ["tip"]

  show(event) {
    const lines = (event.currentTarget.dataset.tip || "").split("\n")
    const tip = this.tipTarget
    tip.replaceChildren()
    lines.forEach((text, i) => {
      const d = document.createElement("div")
      d.className = i === 0 ? "font-semibold" : "text-slate-600"
      d.textContent = text
      tip.appendChild(d)
    })
    tip.hidden = false
    this.move(event)
  }

  move(event) {
    const tip = this.tipTarget, box = this.element.getBoundingClientRect()
    let x, y
    if (event.type === "focus" || event.clientX === undefined) {
      const r = event.currentTarget.getBoundingClientRect(); x = r.left - box.left + 10; y = r.bottom - box.top + 6
    } else { x = event.clientX - box.left + 12; y = event.clientY - box.top + 12 }
    tip.style.left = `${Math.max(4, Math.min(x, box.width - tip.offsetWidth - 4))}px`
    tip.style.top = `${y}px`
  }

  hide() { this.tipTarget.hidden = true }
}
