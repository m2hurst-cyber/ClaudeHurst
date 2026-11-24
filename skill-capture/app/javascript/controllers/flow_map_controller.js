import { Controller } from "@hotwired/stimulus"
import { LANES, stepFrom, newId, insertAt, move, remove, update, gapIndex, layout, problems, shiftLane, isPause, pauseLabel } from "addin/flow_model"

// The process map: lanes (where the work happens) × order (left to right). Drag a skill or a blank task
// from the palette onto a lane; drag tasks to reorder them or move them to another lane; click a task to
// edit it. Save writes the steps; Run starts them in order, each handing off to the next.
const W = 214, H = 96, LABEL = 110, NODE_W = 160, NODE_H = 64

export default class extends Controller {
  static targets = ["canvas", "svg", "nodes", "marker", "editor", "status", "name", "filter", "paletteItem", "save", "run", "live", "estimate"]
  static values = { steps: Array, url: String, assignees: Array, skills: Array, runUrl: String, run: Object, estimate: Object, natures: Array, models: Array, macros: Object }

  connect() {
    this.steps = this.stepsValue
    this.selected = null
    this.dirty = false
    this.live = this.runValue && this.runValue.id ? this.runValue : null
    this.est = this.estimateValue || {}
    this.render()
    window.addEventListener("beforeunload", this.warn = (e) => { if (this.dirty) { e.preventDefault(); e.returnValue = "" } })
    if (this.live) this.poll = setInterval(() => this.refreshLive(), 10000)
  }
  disconnect() { window.removeEventListener("beforeunload", this.warn); clearInterval(this.poll) }

  // A run of this flow is active: show which task is running now (and what's done), refreshed every 10 s.
  async refreshLive() {
    try {
      const r = await fetch(this.live.json_url, { headers: { Accept: "application/json" } })
      if (!r.ok) return
      const d = await r.json()
      this.live = { ...this.live, ...d }
      if (!["running", "on_hold"].includes(d.status)) clearInterval(this.poll)
      this.renderMap()
    } catch { /* offline */ }
  }

  liveState(id) {
    if (!this.live) return null
    const i = this.live.ids.indexOf(id)
    return i < 0 ? null : { state: this.live.states[i], current: i === this.live.current_index && ["running", "on_hold"].includes(this.live.status) }
  }

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
    const val = f === "skill_name" ? (v || undefined) : f === "pause_minutes" ? Number(v) : v
    this.change(update(this.steps, this.selected, { [f]: val, ...(f === "pause_mode" && v === "timer" && !this.steps.find((s) => s.id === this.selected).pause_minutes ? { pause_minutes: 30 } : {}) }), { keepEditor: f !== "pause_mode" })
  }
  nudge(e) {
    const i = this.steps.findIndex((s) => s.id === this.selected)
    if (i < 0) return
    this.change(move(this.steps, this.selected, i + Number(e.currentTarget.dataset.by)))
  }
  addPart() {
    const s = this.steps.find((x) => x.id === this.selected)
    if (!s) return
    const parts = (s.parts || []).slice()
    if (parts.length >= 4) return this.status("At most four parts.", true)
    if (!parts.length) parts.push({ id: newId().slice(0, 6), title: s.title, engine: "ai", assignee: s.assignee || "me" })
    parts.push({ id: newId().slice(0, 6), title: parts.length === 1 ? "Second part" : `Part ${parts.length + 1}`, engine: parts.length === 1 ? "macro" : "ai", assignee: s.assignee || "me" })
    this.change(update(this.steps, this.selected, { parts }))
  }

  removePart(e) {
    e.stopPropagation()
    const s = this.steps.find((x) => x.id === this.selected)
    const parts = (s.parts || []).filter((p) => p.id !== e.currentTarget.dataset.id)
    this.change(update(this.steps, this.selected, { parts: parts.length === 1 ? [] : parts }))
  }

  editPart(e) {
    const box = e.target.closest("[data-part]")
    if (!box || !e.target.name) return
    const s = this.steps.find((x) => x.id === this.selected)
    const parts = (s.parts || []).map((p) => (p.id === box.dataset.part ? { ...p, [e.target.name]: e.target.value } : p))
    this.change(update(this.steps, this.selected, { parts }), { keepEditor: e.target.name !== "engine" })
  }

  removeSelected() { this.change(remove(this.steps, this.selected)); this.selected = null; this.render() }
  removeNode(e) { e.stopPropagation(); const id = e.currentTarget.dataset.id; if (this.selected === id) this.selected = null; this.change(remove(this.steps, id)) }
  key(e) {
    const id = e.currentTarget.dataset.id, i = this.steps.findIndex((s) => s.id === id)
    const k = e.key
    if (k === "Delete" || k === "Backspace") { e.preventDefault(); this.selected = null; this.change(remove(this.steps, id)); return }
    if (k === "ArrowLeft" || k === "ArrowRight") { e.preventDefault(); this.selected = id; this.change(move(this.steps, id, i + (k === "ArrowLeft" ? -1 : 1))); this.focusNode(id); return }
    if (k === "ArrowUp" || k === "ArrowDown") { e.preventDefault(); this.selected = id; this.change(shiftLane(this.steps, id, k === "ArrowUp" ? -1 : 1)); this.focusNode(id) }
  }
  focusNode(id) { this.nodesTarget.querySelector(`[data-id="${CSS.escape(id)}"]`)?.focus() }
  runFrom(e) {
    if (this.dirty) { this.status("Save before running.", true); return }
    const i = this.steps.findIndex((s) => s.id === this.selected)
    const f = document.createElement("form")
    f.method = "post"; f.action = `${this.runUrlValue}?from=${i}${e.currentTarget.dataset.only ? "&only=1" : ""}`
    f.innerHTML = `<input type="hidden" name="authenticity_token" value="${document.querySelector("meta[name=csrf-token]")?.content || ""}">`
    document.body.appendChild(f); f.submit()
  }
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
    this.est = body.estimate || this.est
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
      const s = n.step, p = pos[n.id], pause = isPause(s), live = this.liveState(s.id)
      const el = document.createElement("div")
      el.tabIndex = 0; el.draggable = true; el.dataset.node = ""; el.dataset.id = s.id
      el.dataset.action = "dragstart->flow-map#dragNode click->flow-map#pick keydown->flow-map#key"
      el.setAttribute("role", "button")
      el.setAttribute("aria-label", `Task ${i + 1}: ${s.title} (${pause ? pauseLabel(s) : s.app})${live?.current ? ", running now" : live ? `, ${live.state}` : ""}. Arrow keys move it, Delete removes it.`)
      const ring = live?.current ? "ring-4 ring-amber-400 border-amber-500" : this.selected === s.id ? "ring-2 ring-sky-600 border-sky-600" : ""
      const tone = live?.state === "done" ? "bg-emerald-50 border-emerald-500" : live?.state === "skipped" ? "bg-slate-50 opacity-50" : pause ? "bg-amber-50 border-dashed border-amber-500" : "bg-white border-slate-300"
      el.className = `group absolute text-left rounded border shadow-sm px-2 py-1 text-xs hover:border-slate-500 cursor-grab focus:outline-none focus-visible:ring-2 focus-visible:ring-sky-600 ${tone} ${ring}`
      Object.assign(el.style, { left: `${p.x}px`, top: `${p.y}px`, width: `${NODE_W}px`, height: `${NODE_H}px` })
      const badge = live?.current ? (live.state === "paused" ? '<span class="text-amber-800 font-semibold">⏸ waiting now</span>' : this.live.status === "on_hold" ? '<span class="text-amber-800 font-semibold">⏸ run on hold</span>' : '<span class="inline-flex items-center gap-1 text-amber-800 font-semibold"><span class="w-2 h-2 rounded-full bg-amber-500 animate-pulse"></span>running now</span>')
        : live?.state === "done" ? '<span class="text-emerald-700">✓ done</span>' : live?.state === "skipped" ? '<span class="text-slate-500">skipped</span>' : ""
      el.innerHTML = `<div class="flex gap-1 items-start pr-4"><span class="shrink-0 w-4 h-4 rounded-full ${pause ? "bg-amber-600" : "bg-slate-900"} text-white grid place-items-center" style="font-size:9px">${pause ? "⏸" : i + 1}</span><span class="font-medium leading-tight line-clamp-2">${esc(s.title)}</span></div>
        <div class="text-slate-500 truncate mt-0.5">${badge || esc(pause ? pauseLabel(s) : (s.parts || []).length >= 2 ? `⇶ ${s.parts.length} parts: ${s.parts.map((p) => ({ macro: "⚙", ai: "🤖", person: "🧑" })[p.engine] || "🤖").join(" ")}` : `${s.engine === "macro" ? "⚙ macro · " : ""}${who[s.assignee] || s.assignee}${s.skill_name ? " · 📘" : ""}`)}</div>
        ${pause ? "" : `<div class="text-[10px] text-slate-400 truncate">${(this.stepEstimate(i) || {}).engine === "macro" ? "no tokens" : `${Number((this.stepEstimate(i) || {}).tokens || 0).toLocaleString()} tok · ${Number((this.stepEstimate(i) || {}).cost || 0).toFixed(2)} cr`}</div>`}
        <button type="button" data-id="${esc(s.id)}" data-action="click->flow-map#removeNode" class="absolute top-0.5 right-1 text-slate-400 hover:text-red-700 opacity-0 group-hover:opacity-100 group-focus:opacity-100 ${this.selected === s.id ? "opacity-100" : ""}" aria-label="Delete task ${i + 1}" title="Delete (or press Delete)">✕</button>`
      this.nodesTarget.appendChild(el)
    })
    if (this.hasLiveTarget) {
      const cur = this.live && ["running", "on_hold"].includes(this.live.status) ? this.live.current_index : null
      this.liveTarget.hidden = cur === null
      if (cur !== null) this.liveTarget.querySelector("[data-live-text]").textContent = `${this.live.status === "on_hold" ? "On hold at" : "Running now:"} task ${cur + 1}, ${this.live.titles[cur] || ""}`
    }
    this.renderEstimate()
    if (!this.steps.length) this.status("Drag a skill or a blank task onto a lane to start.")
  }

  stepEstimate(i) { return (this.est.steps || [])[i] }

  renderEstimate() {
    if (!this.hasEstimateTarget) return
    const e = this.est
    if (!e || !e.steps) { this.estimateTarget.textContent = ""; return }
    const mins = Math.round((e.seconds || 0) / 60)
    this.estimateTarget.innerHTML = `Anticipated <strong>${Number(e.tokens || 0).toLocaleString()}</strong> tokens · <strong>${Number(e.cost || 0).toFixed(2)}</strong> credits · ~${mins} min${e.macro_steps ? ` · <span class="text-emerald-700">${e.macro_steps} macro</span>` : ""}${this.dirty ? " (before your changes)" : ""}`
  }

  renderEditor() {
    const s = this.steps.find((x) => x.id === this.selected)
    if (!s) { this.editorTarget.innerHTML = '<p class="text-slate-500">Select a task to edit it. Drag tasks to reorder them or move them to another lane.</p>'; return }
    const i = this.steps.indexOf(s)
    const esc = (v) => String(v ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]))
    const opt = (v, l, cur) => `<option value="${esc(v)}" ${v === cur ? "selected" : ""}>${esc(l)}</option>`
    const est = this.stepEstimate(i) || {}
    const macro = (this.macrosValue || {})[s.id]
    const parts = s.parts || []
    const whoOpts = (cur) => this.assigneesValue.map((a) => opt(a.value, a.label, cur)).join("")
    const modelOpts = (cur) => `<option value="">Auto: cheapest that fits</option>${this.modelsValue.filter((m) => m.key !== "macro").map((m) => opt(m.key, `${m.name} (${m.tier})`, cur || "")).join("")}`
    this.editorTarget.innerHTML = `
      <div class="flex items-center justify-between mb-2"><h3 class="font-semibold">Task ${i + 1}</h3>        <div class="flex gap-1"><button type="button" data-action="flow-map#nudge" data-by="-1" class="px-2 py-0.5 border rounded" aria-label="Move earlier">←</button><button type="button" data-action="flow-map#nudge" data-by="1" class="px-2 py-0.5 border rounded" aria-label="Move later">→</button></div></div>
      <div class="space-y-2" data-action="input->flow-map#edit change->flow-map#edit">
        <label class="block">Title<input name="title" value="${esc(s.title)}" class="mt-1 w-full border rounded px-2 py-1"></label>
        <label class="block">Where (lane)<select name="app" class="mt-1 w-full border rounded px-2 py-1">${LANES.map((l) => opt(l, l, s.app)).join("")}</select></label>
        ${isPause(s) ? `
        <label class="block">Pause until<select name="pause_mode" class="mt-1 w-full border rounded px-2 py-1">${opt("manual", "Someone resumes it", s.pause_mode)}${opt("timer", "A set time has passed", s.pause_mode)}</select></label>
        ${s.pause_mode === "timer" ? `<label class="block">Minutes<input name="pause_minutes" type="number" min="1" max="10080" value="${esc(s.pause_minutes || 30)}" class="mt-1 w-full border rounded px-2 py-1"></label>` : ""}` : `
        <label class="block">Who does it<select name="assignee" class="mt-1 w-full border rounded px-2 py-1">${this.assigneesValue.map((a) => opt(a.value, a.label, s.assignee)).join("")}</select></label>
        <label class="block">Skill to follow<select name="skill_name" class="mt-1 w-full border rounded px-2 py-1"><option value="">None</option>${this.skillsValue.map((k) => opt(k.name, k.title, s.skill_name || "")).join("")}</select></label>
        <div class="grid grid-cols-2 gap-1">
          <label class="block">Nature<select name="nature" class="mt-1 w-full border rounded px-2 py-1" title="What kind of thinking this needs">${opt("", `Auto: ${est.nature || "—"}`, s.nature || "")}${this.naturesValue.map((n) => opt(n.value, n.label, s.nature || "")).join("")}</select></label>
          <label class="block">Complexity<select name="complexity" class="mt-1 w-full border rounded px-2 py-1">${opt("", `Auto: ${est.complexity || "—"}`, s.complexity || "")}${["low", "medium", "high"].map((c) => opt(c, c, s.complexity || "")).join("")}</select></label>
        </div>
        <label class="block">Runs on<select name="engine" class="mt-1 w-full border rounded px-2 py-1">${opt("", "Auto (macro if one is approved)", s.engine || "")}${opt("ai", "🤖 AI", s.engine || "")}${opt("macro", "⚙ Macro (no AI)", s.engine || "")}${opt("person", "🧑 Person", s.engine || "")}</select></label>
        <label class="block">Model<select name="model" class="mt-1 w-full border rounded px-2 py-1">${modelOpts(s.model)}</select></label>`}
        <label class="block">${isPause(s) ? "Note" : "Instructions"}<textarea name="instructions" rows="3" class="mt-1 w-full border rounded px-2 py-1">${esc(s.instructions)}</textarea></label>
      </div>
      ${isPause(s) ? "" : `
      <div class="mt-3 rounded border bg-slate-50 p-2 text-xs">
        <div class="font-medium mb-0.5">Anticipated ${est.engine === "macro" ? "— macro, no tokens" : `${Number(est.tokens || 0).toLocaleString()} tokens · ${Number(est.cost || 0).toFixed(3)} credits · ~${Math.round(est.seconds || 0)} s`}</div>
        ${est.nature ? `<div class="text-slate-600">${esc(est.nature)} · ${esc(est.complexity || "")}</div>` : ""}
        <div class="text-slate-600">${esc(est.basis || "saves to see the estimate")}${est.model ? ` · ${esc(est.model)}` : ""}</div>
        ${macro ? `<a href="${esc(macro.url)}" class="text-sky-700 hover:underline">Macro review: ${esc(macro.status)} (${esc(macro.verdict)})</a>` : ""}
      </div>
      <div class="mt-3">
        <div class="flex items-center justify-between"><h4 class="font-medium">Split into parts</h4>
          <button type="button" data-action="flow-map#addPart" class="px-2 py-0.5 rounded border text-xs">＋ Part</button></div>
        <p class="text-xs text-slate-500">Two agents, or an AI and a macro, side by side. The task hands off when every part is done.</p>
        ${parts.length ? `<div class="space-y-1 mt-1" data-action="input->flow-map#editPart change->flow-map#editPart">
          ${parts.map((p, pi) => `<div class="border rounded p-1.5 bg-white" data-part="${esc(p.id)}">
            <div class="flex gap-1 items-center"><span class="text-xs text-slate-500">${pi + 1}</span>
              <input name="title" value="${esc(p.title)}" class="flex-1 border rounded px-1 py-0.5 text-xs" aria-label="Part title">
              <button type="button" data-action="flow-map#removePart" data-id="${esc(p.id)}" class="text-slate-400 hover:text-red-700" aria-label="Remove part">✕</button></div>
            <div class="flex gap-1 mt-1">
              <select name="engine" class="flex-1 border rounded px-1 py-0.5 text-xs" aria-label="Runs on">${opt("ai", "🤖 AI", p.engine)}${opt("macro", "⚙ Macro", p.engine)}${opt("person", "🧑 Person", p.engine)}</select>
              <select name="assignee" class="flex-1 border rounded px-1 py-0.5 text-xs" aria-label="Who">${whoOpts(p.assignee)}</select>
            </div>
            ${p.engine === "ai" ? `<select name="model" class="w-full mt-1 border rounded px-1 py-0.5 text-xs" aria-label="Model">${modelOpts(p.model)}</select>` : ""}
          </div>`).join("")}</div>` : ""}
      </div>
      <div class="flex gap-1 mt-3"><button type="button" data-action="flow-map#runFrom" class="flex-1 px-2 py-1 rounded bg-emerald-700 text-white text-xs">▶ Run from here</button><button type="button" data-action="flow-map#runFrom" data-only="1" class="flex-1 px-2 py-1 rounded border text-xs">Run just this task</button></div>`}
      <button type="button" data-action="flow-map#removeSelected" class="mt-2 text-red-700 text-xs hover:underline">Delete ${isPause(s) ? "pause" : "task"}</button>
      <p class="text-xs text-slate-500 mt-2">Keyboard: ←/→ reorder · ↑/↓ change lane · Delete removes.</p>`
  }
}
