import { Controller } from "@hotwired/stimulus"

// "Copy for LLM ▾": copy the page's Markdown (fetched from its .md URL), view it as .md, or copy the link.
export default class extends Controller {
  static targets = ["button", "label", "chevron", "menu", "dialog", "pre", "status"]
  static values = { url: String, filename: String }

  connect() { this.outside = (e) => { if (!this.element.contains(e.target)) this.hideMenu() }; document.addEventListener("click", this.outside) }
  disconnect() { document.removeEventListener("click", this.outside) }

  async markdown() {
    if (this.text != null) return this.text
    const r = await fetch(this.urlValue, { headers: { Accept: "text/markdown" } })
    if (!r.ok) throw new Error(`Couldn't load the Markdown (${r.status})`)
    this.text = await r.text()
    return this.text
  }

  async write(text) {
    try { await navigator.clipboard.writeText(text); return true } catch {
      const t = document.createElement("textarea")
      t.value = text; t.setAttribute("readonly", ""); t.style.position = "fixed"; t.style.opacity = "0"
      document.body.appendChild(t); t.select()
      const ok = document.execCommand("copy"); t.remove(); return ok
    }
  }

  flashLabel(text) {
    const old = "Copy for LLM"
    this.labelTarget.textContent = text
    clearTimeout(this.t); this.t = setTimeout(() => { this.labelTarget.textContent = old }, 2000)
  }

  async copy() {
    try { this.flashLabel((await this.write(await this.markdown())) ? "Copied ✓" : "Copy failed") } catch (e) { this.flashLabel("Copy failed") }
  }

  toggle(e) {
    e.stopPropagation()
    this.menuTarget.hidden ? this.showMenu() : this.hideMenu()
  }
  showMenu() { this.menuTarget.hidden = false; this.chevronTarget.setAttribute("aria-expanded", "true"); this.menuTarget.querySelector("[role=menuitem]")?.focus() }
  hideMenu() { this.menuTarget.hidden = true; this.chevronTarget.setAttribute("aria-expanded", "false") }

  async view() {
    this.hideMenu()
    this.preTarget.textContent = "Loading…"
    this.statusTarget.textContent = ""
    this.dialogTarget.showModal()
    try { this.preTarget.textContent = await this.markdown() } catch (e) { this.preTarget.textContent = e.message }
  }
  close() { this.dialogTarget.close() }

  async copyFromDialog() {
    const ok = await this.write(await this.markdown())
    this.statusTarget.textContent = ok ? "Copied ✓" : "Copy failed"
  }

  async copyLink() {
    this.hideMenu()
    const ok = await this.write(new URL(this.urlValue, location.href).href)
    this.flashLabel(ok ? "Link copied ✓" : "Copy failed")
  }
}
