import { Controller } from "@hotwired/stimulus"

// Send skills: filter the list, count the selection, and switch the price on only when every selected
// skill can be sold by this person.
export default class extends Controller {
  static targets = ["item", "count", "price", "paid", "priceHint"]

  connect() { this.count() }

  filter(e) {
    const q = e.target.value.trim().toLowerCase()
    this.itemTargets.forEach((li) => { li.hidden = q !== "" && !li.dataset.text.includes(q) })
  }

  count() {
    const boxes = [...this.element.querySelectorAll("input[name='skills[]']:checked")]
    this.countTarget.textContent = boxes.length ? `· ${boxes.length} selected` : ""
    const sellable = boxes.length > 0 && boxes.every((b) => b.dataset.sellable === "true")
    this.paidTarget.disabled = !sellable
    if (!sellable && this.paidTarget.checked) { this.element.querySelector("input[name=pricing][value=free]").checked = true; this.pricing() }
  }

  pricing() {
    const paid = this.paidTarget.checked
    this.priceTarget.disabled = !paid
    if (!paid) this.priceTarget.value = ""
  }
}
