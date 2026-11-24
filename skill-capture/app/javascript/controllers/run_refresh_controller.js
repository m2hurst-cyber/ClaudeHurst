import { Controller } from "@hotwired/stimulus"

// Keeps a flow run's page current: checks every 10 s and reloads when the run has moved on (a task was
// done by someone else, an agent finished, a timed pause ended), unless you're typing.
export default class extends Controller {
  static values = { url: String, stamp: Number }

  connect() { this.timer = setInterval(() => this.check(), 10000) }
  disconnect() { clearInterval(this.timer) }

  async check() {
    const busy = [...this.element.querySelectorAll("textarea, input[type=text], input:not([type])")].some((el) => el.value.trim() !== "" || el === document.activeElement)
    if (busy || document.hidden) return
    try {
      const r = await fetch(this.urlValue, { headers: { Accept: "application/json" } })
      if (!r.ok) return
      const d = await r.json()
      if (d.updated_at !== this.stampValue) window.Turbo ? window.Turbo.visit(location.href, { action: "replace" }) : location.reload()
      if (!["running", "on_hold"].includes(d.status)) clearInterval(this.timer)
    } catch { /* offline */ }
  }
}
