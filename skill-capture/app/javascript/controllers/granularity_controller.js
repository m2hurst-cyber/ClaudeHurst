import { Controller } from "@hotwired/stimulus"

// The granularity slider. Moving it rewrites the description underneath and says what that
// setting would have found in the events already collected, so the choice is made against
// evidence rather than a guess.
export default class extends Controller {
  static targets = ["slider", "tick", "blurb", "detail", "cost"]
  static values = { previewUrl: String }

  connect() {
    this.levels = {
      1: { blurb: "The smallest thing worth naming. Many small skills that compose; the map does the joining.",
           detail: "2–3 steps · must appear in 3 different surroundings · twice the usual evidence" },
      2: { blurb: "Short, nameable procedures that show up inside several larger jobs.",
           detail: "2–4 steps · must appear in 2 different surroundings · half again the usual evidence" },
      3: { blurb: "What a person would call a task: a recognisable job with an outcome.",
           detail: "2–6 steps · the usual evidence · overlapping windows stitched back together · today's behaviour" },
      4: { blurb: "Larger procedures that carry a piece of work from input to deliverable.",
           detail: "3–9 steps · a little less evidence, since long runs repeat less often" },
      5: { blurb: "Few, long skills: a whole engagement or close, start to finish.",
           detail: "4–14 steps · least evidence · the longest version of a pattern always wins" }
    }
    this.load()
  }

  async load() {
    try {
      const response = await fetch(this.previewUrlValue, { headers: { Accept: "application/json" } })
      this.preview = await response.json()
    } catch { this.preview = null }
    this.change()
  }

  change() {
    const level = this.sliderTarget.value
    const copy = this.levels[level]
    this.blurbTarget.textContent = copy.blurb
    this.detailTarget.textContent = copy.detail
    this.tickTargets.forEach((t) => {
      t.classList.toggle("font-semibold", t.dataset.level === level)
      t.classList.toggle("text-slate-900", t.dataset.level === level)
    })
    if (!this.preview) { this.costTarget.textContent = ""; return }
    const p = this.preview[level]
    if (!p) { this.costTarget.textContent = ""; return }
    const sample = p.samples?.[0]
    this.costTarget.textContent = p.count === 0
      ? "Nothing in the last 30 days would have been picked up at this setting."
      : `Would have found ${p.count} ${p.count === 1 ? "pattern" : "patterns"} in the last 30 days, ` +
        `typically ${p.median_steps} steps${sample ? `. For example: ${sample.title}` : ""}`
  }
}
