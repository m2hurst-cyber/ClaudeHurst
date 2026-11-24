import { Controller } from "@hotwired/stimulus"
import { LANES, stepFrom, insertAt, move, remove, update, gapIndex, layout, problems } from "addin/flow_model"

// The process map: lanes (where the work happens) × order (left to right). Drag a skill or a blank task
// from the palette onto a lane; drag tasks to reorder them or move them to another lane; click a task to
// edit it. Save writes the steps; Run starts them in order, each handing off to the next.
const W = 214, H = 96, LABEL = 110, NODE_W = 160, NODE_H = 64

export default class extends Controller {
  static targets = ["canvas", "svg", "nodes", "marker", "editor", "status", "name", "filter", "paletteItem", "save", "run"]
  static values = { steps: Array, url: String, assignees: Array, skills: Array }

  connect() {
    this.steps = this.stepsValue
    this.selected = null
    this.dirty = false
    this.render()
    window.addEventListener("beforeunload", this.warn = (e) => { if (this.dirty) { e.preventDefault(); e.returnValue = "" } })
  }
  disconnect() { window.removeEventListener("beforeunload", this.warn) }

  // ---------- palette ----------
  filter() {
    const q = this.filterTarget.value.trim().toLowerCase()
    this.paletteItemTargets.forEach((el) => { el.hidden = q && !el.dataset.text.includes(q) })
  }
  dragPalette(e) { e.dataTransfer.setData("text/plain", JSON.stringify({ palette: JSON.parse(e.currentTarget.dataset.item) })); e.dataTransfer.effectAllowed = "copy" }
  addFromPalette(e) { // keyboard / click: append to the end
    const item = JSON.parse(e.currentTarget.dataset.item)
    const s = stepFrom(item)
    this.change(insertAt(this.steps, this.steps.length, s)); this.select(s.id)
  }

  // ---------- canvas drag and drop ----------
  dragNode(e) { e.dataTransfer.setData("text/plain", JSON.stringify({ node: e.currentTarget.dataset.id })); e.dataTransfer.effectAllowed = "move" }
  where(e) {
    const r = this.canvasTarget.getBoundingClientRect()
    const x = e.clientX - r.left + this.canvasTarget.scrollLeft - LABEL, y = e.clientY - r.top + this.canvasTarget.scrollTop
    const lane = LANES[Math.max(0, Math.min(LANES.length - 1, Math.floor(y / H)))]
    const gap = gapIndex(this.steps.map((_, i) => i * W + W / 2), x)
    return { lane, gap }
  }
  over(e) {
    e.preventDefault()
    const { lane, gap } = this.where(e)
    Object.assign(this.markerTarget.style, { display: "block", left: `${LABEL + gap * W - 6}px`, top: `${LANES.indexOf(lane) * H + 8}px`, height: `${H - 16}px` })
  }
  leave() { this.markerTarget.style.display = "none" }
  drop(e) {
    e.preventDefault(); this.leave()
    let data; try { data = JSON.parse(e.dataTransfer.getData("text/plain")) } catch { return }
    const { lane, gap } = this.where(e)
    if (data.palette) {
      const s = stepFrom(data.palette, lane)
      this.change(insertAt(this.steps, gap, s)); this.select(s.id)
    } else if (data.node) {
      const from = this.steps.findIndex((s) => s.id === data.node)
      this.change(move(this.steps, data.node, from < gap ? gap - 1 : gap, lane)); this.select(data.node)
    }
  }

  // ---------- editing ----------
  pick(e) { this.select(e.currentTarget.dataset.id) }
  select(id) { this.selected = id; this.render() }
  edit(e) {
    const f = e.target.name
    if (!this.selected || !f) return
    const v = e.target.value
    this.change(update(this.steps, this.selected, { [f]: f === "skill_name" ? (v || undefined) : v }), { keepEditor: true })
  }
  nudge(e) {
    const i = this.steps.findIndex((s) => s.id === this.selected)
    if (i < 0) return
    this.change(move(this.steps, this.selected, i + Number(e.currentTarget.dataset.by)))
  }
  removeSelected() { this.change(remove(this.steps, this.selected)); this.selected = null; this.render() }
  rename() { this.dirty = true; this.status("Unsaved changes") }

  change(steps, { keepEditor = false } = {}) {
    this.steps = steps; this.dirty = true
    this.status("Unsaved changes")
    keepEditor ? this.renderMap() : this.render()
  }

  async save() {
    const errs = problems(this.steps)
    if (errs.length) return this.status(errs.join(" "), true)
    const token = document.querySelector("meta[name=csrf-token]")?.content
    const res = await fetch(this.urlValue, { method: "PATCH", headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": token },
                                              body: JSON.stringify({ name: this.nameTarget.value, steps: this.steps }) })
    const body = await res.json().catch(() => ({}))
    if (!res.ok) return this.status(body.error || "Couldn't save", true)
    this.steps = body.steps; this.dirty = false
    this.status("Saved"); this.render()
  }
  beforeRun(e) { if (this.dirty) { e.preventDefault(); this.status("Save before running.", true) } }

  status(text, bad = false) { this.statusTarget.textContent = text; this.statusTarget.className = `text-xs ${bad ? "text-red-700" : "text-slate-500"}` }

  // ---------- drawing ----------
  render() { this.renderMap(); this.renderEditor() }

  renderMap() {
    const { nodes, edges } = layout(this.steps)
    const width = LABEL + Math.max(this.steps.length + 1, 5) * W, height = LANES.length * H
    this.nodesTarget.style.width = `${width}px`; this.nodesTarget.style.height = `${height}px`
    this.svgTarget.setAttribute("width", width); this.svgTarget.setAttribute("height", height)
    const pos = Object.fromEntries(nodes.map((n) => [n.id, { x: LABEL + n.col * W + (W - NODE_W) / 2, y: n.row * H + (H - NODE_H) / 2 }]))
    const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]))
    const who = Object.fromEntries(this.assigneesValue.map((a) => [a.value, a.label]))
    const lanes = LANES.map((l, i) => `<rect x="0" y="${i * H}" width="${width}" height="${H}" class="${i % 2 ? "fill-slate-50" : "fill-white"}"/>
      <text x="12" y="${i * H + H / 2 + 4}" class="fill-slate-500 text-xs font-medium">${l}</text>
      <line x1="${LABEL - 8}" y1="${i * H}" x2="${LABEL - 8}" y2="${(i + 1) * H}" class="stroke-slate-200"/>`).join("")
    const lines = edges.map((e) => {
      const a = pos[e.from], b = pos[e.to]
      const x1 = a.x + NODE_W, y1 = a.y + NODE_H / 2, x2 = b.x, y2 = b.y + NODE_H / 2, mx = (x1 + x2) / 2
      return `<path d="M${x1},${y1} C${mx},${y1} ${mx},${y2} ${x2 - 6},${y2}" fill="none" stroke-width="2" class="${e.crossing ? "stroke-sky-600" : "stroke-slate-400"}" ${e.crossing ? 'stroke-dasharray="5 4"' : ""} marker-end="url(#arrow)"/>
        ${e.crossing ? (y1 === y2 ? `<text x="${mx}" y="${y1 - 8}" text-anchor="middle" class="fill-sky-700" style="font-size:10px">handoff</text>`
                                  : `<text x="${mx + 5}" y="${(y1 + y2) / 2}" class="fill-sky-700" style="font-size:10px">handoff</text>`) : ""}`
    }).join("")
    this.svgTarget.innerHTML = `<defs><marker id="arrow" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" class="fill-slate-500"/></marker></defs>${lanes}${lines}`
    this.nodesTarget.querySelectorAll("[data-node]").forEach((n) => n.remove())
    nodes.forEach((n, i) => {
      const s = n.step, p = pos[n.id]
      const el = document.createElement("button")
      el.type = "button"; el.draggable = true; el.dataset.node = ""; el.dataset.id = s.id
      el.dataset.action = "dragstart->flow-map#dragNode click->flow-map#pick"
      el.setAttribute("aria-label", `Task ${i + 1}: ${s.title} (${s.app})`)
      el.className = `absolute text-left rounded border bg-white shadow-sm px-2 py-1 text-xs hover:border-slate-500 cursor-grab ${this.selected === s.id ? "ring-2 ring-sky-600 border-sky-600" : "border-slate-300"}`
      Object.assign(el.style, { left: `${p.x}px`, top: `${p.y}px`, width: `${NODE_W}px`, height: `${NODE_H}px` })
      el.innerHTML = `<div class="flex gap-1 items-start"><span class="shrink-0 w-4 h-4 rounded-full bg-slate-900 text-white grid place-items-center" style="font-size:9px">${i + 1}</span><span class="font-medium leading-tight line-clamp-2">${esc(s.title)}</span></div>
        <div class="text-slate-500 truncate mt-0.5">${esc(who[s.assignee] || s.assignee)}${s.skill_name ? " · 📘" : ""}</div>`
      this.nodesTarget.appendChild(el)
    })
    if (!this.steps.length) this.status("Drag a skill or a blank task onto a lane to start.")
  }

  renderEditor() {
    const s = this.steps.find((x) => x.id === this.selected)
    if (!s) { this.editorTarget.innerHTML = '<p class="text-slate-500">Select a task to edit it. Drag tasks to reorder them or move them to another lane.</p>'; return }
    const i = this.steps.indexOf(s)
    const esc = (v) => String(v ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]))
    const opt = (v, l, cur) => `<option value="${esc(v)}" ${v === cur ? "selected" : ""}>${esc(l)}</option>`
    this.editorTarget.innerHTML = `
      <div class="flex items-center justify-between mb-2"><h3 class="font-semibold">Task ${i + 1}</h3>
        <div class="flex gap-1"><button type="button" data-action="flow-map#nudge" data-by="-1" class="px-2 py-0.5 border rounded" aria-label="Move earlier">←</button><button type="button" data-action="flow-map#nudge" data-by="1" class="px-2 py-0.5 border rounded" aria-label="Move later">→</button></div></div>
      <div class="space-y-2" data-action="input->flow-map#edit change->flow-map#edit">
        <label class="block">Title<input name="title" value="${esc(s.title)}" class="mt-1 w-full border rounded px-2 py-1"></label>
        <label class="block">Where (lane)<select name="app" class="mt-1 w-full border rounded px-2 py-1">${LANES.map((l) => opt(l, l, s.app)).join("")}</select></label>
        <label class="block">Who does it<select name="assignee" class="mt-1 w-full border rounded px-2 py-1">${this.assigneesValue.map((a) => opt(a.value, a.label, s.assignee)).join("")}</select></label>
        <label class="block">Skill to follow<select name="skill_name" class="mt-1 w-full border rounded px-2 py-1"><option value="">None</option>${this.skillsValue.map((k) => opt(k.name, k.title, s.skill_name || "")).join("")}</select></label>
        <label class="block">Instructions<textarea name="instructions" rows="4" class="mt-1 w-full border rounded px-2 py-1">${esc(s.instructions)}</textarea></label>
      </div>
      <button type="button" data-action="flow-map#removeSelected" class="mt-2 text-red-700 text-xs hover:underline">Remove task</button>`
  }
}
