import { Controller } from "@hotwired/stimulus"
import { layout, roadPath, branchPath, branchJunction, trafficWidth, DEFAULTS } from "route_map/layout"
import { renderMarkdown } from "addin/markdown"

const NS = "http://www.w3.org/2000/svg"
const INK = "#0b0b0b", INK_2 = "#52514e", ROAD = "#b8b6b0", ROAD_LINKED = "#d6d3cc", SURFACE = "#f5f4f0", UNPAVED = "#a8a29e"
const SEG = DEFAULTS.segment

const el = (name, attrs = {}, parent) => {
  const e = document.createElementNS(NS, name)
  Object.entries(attrs).forEach(([k, v]) => v != null && e.setAttribute(k, v))
  if (parent) parent.appendChild(e)
  return e
}
const truncate = (s, n) => (s.length > n ? `${s.slice(0, n - 1)}…` : s)
const areaName = (a) => (!a ? "No area" : a === "factset" ? "FactSet" : a.length <= 3 ? a.toUpperCase() : a.split(/[-_\s]+/).map((w) => w[0].toUpperCase() + w.slice(1)).join(" "))

// The route map: skills as road segments, journeys as roads between them,
// branches as side roads, unpublished workflows as unpaved roads.
export default class extends Controller {
  static targets = ["data", "svg", "viewport", "tip", "panel", "from", "to", "modeBtn", "areaLegend", "trafficLegend", "search", "results",
                    "appChip", "stageChip", "fieldButton", "fieldTree", "hideOthers", "filterCount", "bridgeChip", "panelClose", "levelChip", "areaSelect"]
  static values = { routeUrl: String, colors: Object, tiers: Object, currency: String, searchUrl: String, placeUrl: String,
                    sendUrl: String, sentUrl: String, recipients: Array }

  connect() {
    this.map = JSON.parse(this.dataTarget.textContent)
    this.allNodes = this.map.nodes
    this.allEdges = this.map.edges
    this.byId = new Map(this.map.nodes.map((n) => [n.id, n]))
    this.filters = this.readFiltersFromUrl()
    this.syncFilterControls()
    this.geo = layout(this.map.nodes, this.map.edges)
    this.maxTraffic = Math.max(1, ...this.map.edges.map((e) => e.traffic || 0))
    this.focus = null
    this.mode = "area"
    this.draw()
    this.sizeViewport()
    this.fit()
    this.applyFilters({ initial: true })
  }

  // ---------- filters (apps, field hierarchy, stage) ----------
  readFiltersFromUrl() {
    const q = new URLSearchParams(location.search)
    return { apps: new Set(q.getAll("app")), field: q.get("field") || null, stages: new Set(q.getAll("stage")), hide: q.get("hide") === "1",
             bridges: q.get("bridges") === "1", level: q.get("level") || null, area: q.get("area") || null }
  }

  writeFiltersToUrl() {
    const q = new URLSearchParams()
    this.filters.apps.forEach((a) => q.append("app", a))
    if (this.filters.field) q.set("field", this.filters.field)
    this.filters.stages.forEach((s) => q.append("stage", s))
    if (this.filters.hide) q.set("hide", "1")
    if (this.filters.bridges) q.set("bridges", "1")
    if (this.filters.level) q.set("level", this.filters.level)
    if (this.filters.area) q.set("area", this.filters.area)
    history.replaceState(null, "", `${location.pathname}${q.toString() ? `?${q}` : ""}`)
  }

  matches(n) {
    const f = this.filters
    if (f.apps.size && !(n.apps || []).some((a) => f.apps.has(a))) return false
    if (f.field && !(n.fields || []).some((p) => p === f.field || p.startsWith(`${f.field}/`))) return false
    if (f.bridges && !(n.bridge || this.allEdges.some((e) => e.bridge && (e.from === n.id || e.to === n.id)))) return false
    if (f.stages.size && !(n.kind === "skill" && f.stages.has(n.stage))) return false
    if (f.level && !(n.levels || []).includes(f.level)) return false
    if (f.area && n.area !== f.area) return false
    return true
  }

  get filtering() { return this.filters.apps.size || this.filters.field || this.filters.stages.size || this.filters.bridges || this.filters.level || this.filters.area }

  toggleBridges() {
    this.filters.bridges = !this.filters.bridges
    const view = this.view
    this.draw(); this.setView(view) // redraw bridge markers as full labels (or back)
    this.applyFilters()
  }

  toggleApp(e) { const a = e.currentTarget.dataset.app; this.filters.apps.has(a) ? this.filters.apps.delete(a) : this.filters.apps.add(a); this.applyFilters() }
  toggleLevel(e) { const l = e.currentTarget.dataset.level; this.filters.level = this.filters.level === l ? null : l; this.applyFilters() }
  setArea(e) { this.filters.area = e.currentTarget.value || null; this.applyFilters() }
  toggleStage(e) { const s = e.currentTarget.dataset.stage; this.filters.stages.has(s) ? this.filters.stages.delete(s) : this.filters.stages.add(s); this.applyFilters() }
  setField(path) { this.filters.field = path; this.fieldTreeTarget.hidden = true; this.fieldButtonTarget.setAttribute("aria-expanded", "false"); this.applyFilters() }
  clearFilters() { this.filters = { apps: new Set(), field: null, stages: new Set(), hide: false, bridges: false, level: null, area: null }; this.hideOthersTarget.checked = false; this.applyFilters() }

  toggleFieldTree() {
    const open = this.fieldTreeTarget.hidden
    this.renderFieldTree()
    this.fieldTreeTarget.hidden = !open
    this.fieldButtonTarget.setAttribute("aria-expanded", String(open))
  }

  // The hierarchy with how many roads sit in each branch (counting everything below it).
  renderFieldTree() {
    const box = this.fieldTreeTarget
    box.replaceChildren()
    const fields = this.map.fields || []
    const kids = new Map()
    fields.forEach((f) => { const k = f.parent || ""; (kids.get(k) || kids.set(k, []).get(k)).push(f) })
    const skills = this.allNodes.filter((n) => n.kind === "skill")
    const count = (path) => skills.filter((n) => (n.fields || []).some((p) => p === path || p.startsWith(`${path}/`))).length
    const row = (label, path, depth, n) => {
      const b = this.append(box, "button", `w-full text-left flex items-center gap-2 rounded px-2 py-1 hover:bg-slate-50 ${this.filters.field === path ? "bg-slate-900 text-white hover:bg-slate-800" : ""}`)
      b.type = "button"; b.setAttribute("role", "treeitem"); b.setAttribute("aria-level", String(depth + 1))
      b.setAttribute("aria-selected", String(this.filters.field === path))
      b.style.paddingLeft = `${8 + depth * 16}px`
      this.append(b, "span", "flex-1", `${depth ? "› " : ""}${label}`)
      this.append(b, "span", "text-xs tabular-nums opacity-70", String(n))
      b.addEventListener("click", () => this.setField(path))
    }
    row("All fields", null, 0, skills.length)
    const walk = (parent, depth) => (kids.get(parent) || []).sort((a, b) => a.position - b.position || a.name.localeCompare(b.name)).forEach((f) => {
      const n = count(f.path)
      if (n || this.filters.field === f.path) row(f.name, f.path, depth, n)
      walk(f.path, depth + 1)
    })
    walk("", 0)
    const un = skills.filter((n) => !(n.fields || []).length).length
    if (un) this.append(box, "p", "text-xs text-slate-500 px-2 pt-1 border-t mt-1", `${un} not classified yet`)
  }

  syncFilterControls() {
    if (!this.hasAppChipTarget) return
    const on = (b, v) => { b.setAttribute("aria-pressed", String(v)); b.classList.toggle("bg-slate-900", v); b.classList.toggle("text-white", v); b.classList.toggle("bg-white", !v) }
    this.appChipTargets.forEach((b) => on(b, this.filters.apps.has(b.dataset.app)))
    this.stageChipTargets.forEach((b) => on(b, this.filters.stages.has(b.dataset.stage)))
    this.levelChipTargets.forEach((b) => on(b, this.filters.level === b.dataset.level))
    if (this.hasAreaSelectTarget) this.areaSelectTarget.value = this.filters.area || ""
    if (this.hasBridgeChipTarget) on(this.bridgeChipTarget, this.filters.bridges)
    this.hideOthersTarget.checked = this.filters.hide
    const f = (this.map.fields || []).find((x) => x.path === this.filters.field)
    const label = f ? (this.map.nodes.find((n) => n.field === f.path)?.field_label || f.name) : "All fields"
    this.fieldButtonTarget.textContent = `Field: ${f ? (this.fieldLabel(f.path) || label) : label} ▾`
  }

  fieldLabel(path) {
    const byPath = new Map((this.map.fields || []).map((f) => [f.path, f]))
    const parts = []
    let p = path
    while (p && byPath.has(p)) { parts.unshift(byPath.get(p).name); p = byPath.get(p).parent }
    return parts.join(" › ")
  }

  applyFilters(opts = {}) {
    if (!opts.initial) this.filters.hide = this.hideOthersTarget.checked
    this.syncFilterControls()
    if (!opts.initial) this.writeFiltersToUrl()
    const keep = new Set(this.allNodes.filter((n) => this.matches(n)).map((n) => n.id))
    const total = this.allNodes.filter((n) => n.kind === "skill").length
    const shown = this.allNodes.filter((n) => n.kind === "skill" && keep.has(n.id)).length
    this.filterCountTarget.textContent = this.filtering ? `Showing ${shown} of ${total} skills` : `${total} skills`

    const hide = Boolean(this.filters.hide && this.filtering)
    if (hide || this.hidden) { // re-lay out only the matching roads (or restore the full map)
      this.hidden = hide
      this.map.nodes = hide ? this.allNodes.filter((n) => keep.has(n.id)) : this.allNodes
      this.map.edges = hide ? this.allEdges.filter((e) => keep.has(e.from) && keep.has(e.to)) : this.allEdges
      this.byId = new Map(this.map.nodes.map((n) => [n.id, n]))
      this.geo = layout(this.map.nodes, this.map.edges)
      this.draw(); this.sizeViewport(); this.fit()
    }
    this.filterKeep = this.filtering ? keep : null
    this.highlight(this.focus ? [...this.focus.nodes] : null, this.focus ? [...this.focus.edges] : null)
  }

  color(node) {
    if (node.kind === "unpaved") return UNPAVED
    if (this.mode === "traffic") return node.tier ? this.tiersValue[node.tier]?.color || "#d6d3d1" : "#d6d3d1"
    return this.colorsValue[node.area] || "#8a8985"
  }

  setMode(event) {
    this.mode = event.currentTarget.dataset.mode
    this.modeBtnTargets.forEach((b) => {
      const on = b.dataset.mode === this.mode
      b.setAttribute("aria-pressed", on); b.classList.toggle("bg-slate-900", on); b.classList.toggle("text-white", on); b.classList.toggle("bg-white", !on)
    })
    this.areaLegendTarget.hidden = this.mode === "traffic"
    this.trafficLegendTarget.hidden = this.mode !== "traffic"
    const view = this.view
    this.draw(); this.setView(view)
    if (this.focus) this.highlight([...this.focus.nodes], [...this.focus.edges])
  }

  money(v) { return `${Math.round(v * 100) / 100} ${this.currencyValue}` }
  trafficText(n) {
    if (!n.tier) return null
    const t = this.tiersValue[n.tier]
    return `${t.icon} ${t.label} traffic · ${this.money(n.price)} per trip`
  }

  // ---------- drawing ----------
  draw() {
    const svg = this.svgTarget
    svg.replaceChildren()
    const defs = el("defs", {}, svg)
    // Fixed-size chevron (userSpaceOnUse), so it doesn't grow with road width.
    const marker = el("marker", { id: "rm-arrow", viewBox: "0 0 10 10", refX: 10, refY: 5, markerWidth: 9, markerHeight: 9,
      markerUnits: "userSpaceOnUse", orient: "auto" }, defs)
    el("path", { d: "M1,1.5 L8,5 L1,8.5", fill: "none", stroke: "#57534e", "stroke-width": 1.8, "stroke-linecap": "round", "stroke-linejoin": "round" }, marker)

    this.world = el("g", {}, svg)
    const roads = el("g", {}, this.world)
    const sideRoads = el("g", {}, this.world)
    const places = el("g", {}, this.world)
    if (this.geo.looseStartY) {
      const t = el("text", { x: DEFAULTS.padX, y: this.geo.looseStartY - 46, "font-size": 13, fill: INK_2 }, this.world)
      t.textContent = "Not yet connected to other skills"
    }

    this.edgeEls = []
    this.pendingBridgeLabels = []
    this.bridgeLabelEls = []
    for (const e of this.map.edges) {
      const a = this.geo.positions.get(e.from), b = this.geo.positions.get(e.to)
      if (!a || !b) continue
      const g = el("g", { "data-from": e.from, "data-to": e.to, class: "rm-edge" }, e.kind === "branch" ? sideRoads : roads)
      if (e.kind === "branch") {
        const d = branchPath(a, b, SEG)
        el("path", { d, fill: "none", stroke: INK_2, "stroke-width": 2, "stroke-dasharray": "1 5", "stroke-linecap": "round" }, g)
        const j = branchJunction(a, b, SEG)
        el("circle", { cx: j.x, cy: j.y, r: 4, fill: INK_2, stroke: SURFACE, "stroke-width": 2 }, g)
        el("path", { d, fill: "none", stroke: "transparent", "stroke-width": 14 }, g)
      } else {
        const d = roadPath(a, b, SEG)
        const w = trafficWidth(e.traffic, this.maxTraffic)
        if (e.bridge) { // bridge deck: dark rails either side of the road
          el("path", { d, fill: "none", stroke: "#3f3f46", "stroke-width": w + 9, "stroke-linecap": "butt" }, g)
          el("path", { d, fill: "none", stroke: SURFACE, "stroke-width": w + 5, "stroke-linecap": "butt" }, g)
          g.classList.add("rm-bridge")
        }
        el("path", { d, fill: "none", stroke: SURFACE, "stroke-width": w + 4, "stroke-linecap": "round" }, g)
        el("path", { d, fill: "none", stroke: e.traffic ? ROAD : ROAD_LINKED, "stroke-width": w, "stroke-linecap": "round" }, g)
        el("path", { d, fill: "none", stroke: "transparent", "stroke-width": 1, "marker-end": "url(#rm-arrow)" }, g)
        el("path", { d, fill: "none", stroke: "transparent", "stroke-width": Math.max(14, w + 6) }, g)
      }
      if (e.kind === "next" && !e.from.startsWith("candidate:") && !e.to.startsWith("candidate:")) {
        g.classList.add("cursor-pointer")
        g.addEventListener("click", () => this.selectHandoff(e.from, e.to))
      }
      if (e.bridge) this.pendingBridgeLabels.push({ e, g })
      g.addEventListener("pointerenter", (ev) => this.edgeTip(ev, e))
      g.addEventListener("pointermove", (ev) => this.moveTip(ev))
      g.addEventListener("pointerleave", () => this.hideTip())
      this.edgeEls.push({ e, g })
    }

    this.nodeEls = new Map()
    for (const n of this.map.nodes) {
      const p = this.geo.positions.get(n.id)
      const g = el("g", { transform: `translate(${p.x},${p.y})`, "data-id": n.id, tabindex: 0, role: "button", class: "rm-node cursor-pointer",
        "aria-label": `${n.title}, ${areaName(n.area)}${n.kind === "unpaved" ? ", unpaved, in review" : ""}` }, places)
      el("rect", { x: -12, y: -36, width: SEG + 24, height: 70, rx: 8, fill: "transparent" }, g)
      const c = this.color(n)
      if (n.bridge) { // a skill that itself spans fields or apps: bridge rails along the road
        el("line", { x1: -4, y1: 0, x2: SEG + 4, y2: 0, stroke: "#3f3f46", "stroke-width": 18, "stroke-linecap": "butt" }, g)
      }
      el("line", { x1: 0, y1: 0, x2: SEG, y2: 0, stroke: SURFACE, "stroke-width": 14, "stroke-linecap": "round" }, g)
      el("line", { x1: 0, y1: 0, x2: SEG, y2: 0, stroke: c, "stroke-width": n.stage === "local" ? 6 : 10, "stroke-linecap": "round",
        "stroke-dasharray": n.kind === "unpaved" ? "12 9" : null, "stroke-opacity": n.stage === "local" ? 0.6 : 1 }, g)
      for (const x of [0, SEG]) el("circle", { cx: x, cy: 0, r: 5, fill: "#ffffff", stroke: c, "stroke-width": 3 }, g)
      const title = el("text", { x: 0, y: -15, "font-size": 15, "font-weight": 600, fill: INK }, g)
      title.textContent = truncate(n.title, 26)
      const meta = this.mode === "traffic" && n.tier
        ? [`${this.tiersValue[n.tier].icon} ${this.tiersValue[n.tier].label}`, this.money(n.price), n.bounty ? `💰 ${this.money(n.bounty.pool)}` : null].filter(Boolean).join(" · ")
        : [n.bridge ? `⇄ ${n.bridge_label || "bridge"}` : null, n.stage === "local" ? "🧪 local" : n.stage === "market" ? "🌐 market" : null, n.bridge ? null : n.apps?.join(", "), `${n.steps} steps`, n.kind === "unpaved" ? "unpaved" : null,
           n.improvements ? `improved ×${n.improvements}` : null, n.bounty ? "💰 bounty" : null].filter(Boolean).join(" · ")
      const m = el("text", { x: 0, y: 26, "font-size": 12.5, fill: INK_2 }, g)
      m.textContent = meta
      g.addEventListener("pointerenter", (ev) => this.nodeTip(ev, n))
      g.addEventListener("pointermove", (ev) => this.moveTip(ev))
      g.addEventListener("pointerleave", () => this.hideTip())
      g.addEventListener("focus", (ev) => this.nodeTip(ev, n))
      g.addEventListener("blur", () => this.hideTip())
      g.addEventListener("click", () => this.select(n.id))
      g.addEventListener("keydown", (ev) => { if (ev.key === "Enter" || ev.key === " ") { ev.preventDefault(); this.select(n.id) } })
      this.nodeEls.set(n.id, g)
    }

    // Bridge labels at the middle of each bridge road: what it crosses.
    for (const { e, g } of this.pendingBridgeLabels) {
      const path = g.querySelector("path")
      const mid = path.getPointAtLength(path.getTotalLength() / 2)
      const full = this.filters.bridges
      // Straight hops sit between two titled roads, so their label drops below the meta line.
      const straight = this.geo.positions.get(e.from)?.y === this.geo.positions.get(e.to)?.y
      const dy = straight ? 44 : -14
      const lg = el("g", { transform: `translate(${mid.x},${mid.y + (full ? dy : 0)})`, class: "rm-bridge-label pointer-events-none" }, places)
      const t = el("text", { x: 0, y: 4, "font-size": full ? 10.5 : 11, "font-weight": 700, "text-anchor": "middle", fill: INK }, lg)
      t.textContent = full ? `⇄ ${this.bridgeShort(e.bridge)}` : "⇄"
      const bb = t.getBBox()
      lg.insertBefore(full
        ? el("rect", { x: bb.x - 5, y: bb.y - 2, width: bb.width + 10, height: bb.height + 4, rx: 4, fill: "#ffffff", stroke: "#3f3f46", "stroke-width": 1 })
        : el("circle", { cx: 0, cy: 0, r: 9, fill: "#ffffff", stroke: "#3f3f46", "stroke-width": 1.5 }), t)
      this.bridgeLabelEls = this.bridgeLabelEls || []
      this.bridgeLabelEls.push({ e, lg })
    }

    // Intersections: the end of each skill road that has exits (or written directions).
    const written = new Set(this.map.written || [])
    this.junctionEls = new Map()
    for (const n of this.map.nodes) {
      if (n.kind !== "skill") continue
      const exits = this.map.edges.filter((e) => e.from === n.id && e.kind === "next")
      if (!exits.length && !written.has(`junction:${n.id}`)) continue
      const p = this.geo.positions.get(n.id)
      const g = el("g", { transform: `translate(${p.x + SEG},${p.y})`, class: "rm-node rm-junction cursor-pointer", "data-junction": n.id,
        tabindex: 0, role: "button", "aria-label": `Intersection after ${n.title}, ${exits.length} exits` }, places)
      el("circle", { r: 13, fill: "transparent" }, g)
      el("circle", { r: 7, fill: "#ffffff", stroke: INK, "stroke-width": 2.5 }, g)
      el("circle", { r: 2.5, fill: written.has(`junction:${n.id}`) ? INK : "#ffffff" }, g)
      const show = (ev) => this.showTip(ev, [[`Intersection after ${n.title}`, "font-semibold"],
        [`${exits.length} exit${exits.length === 1 ? "" : "s"} · ${written.has(`junction:${n.id}`) ? "directions written" : "generated directions"}`, "text-slate-600"]])
      g.addEventListener("pointerenter", show)
      g.addEventListener("pointermove", (ev) => this.moveTip(ev))
      g.addEventListener("pointerleave", () => this.hideTip())
      g.addEventListener("focus", show)
      g.addEventListener("blur", () => this.hideTip())
      g.addEventListener("click", (ev) => { ev.stopPropagation(); this.selectJunction(n.id) })
      g.addEventListener("keydown", (ev) => { if (ev.key === "Enter" || ev.key === " ") { ev.preventDefault(); this.selectJunction(n.id) } })
      this.junctionEls.set(n.id, g)
    }
  }

  // ---------- highlight ----------
  highlight(nodeIds, edgePairs) {
    this.focus = nodeIds ? { nodes: new Set(nodeIds), edges: new Set(edgePairs || []) } : null
    const keep = this.filterKeep
    const nodeOp = (id) => (keep && !keep.has(id) ? 0.12 : 1) * (!this.focus || this.focus.nodes.has(id) ? 1 : 0.18)
    for (const [id, g] of this.nodeEls) g.style.opacity = nodeOp(id)
    for (const [id, g] of this.junctionEls || []) g.style.opacity = nodeOp(id)
    for (const { e, lg } of this.bridgeLabelEls || []) {
      const vis = (!keep || (keep.has(e.from) && keep.has(e.to))) && (!this.focus || this.focus.edges.has(`${e.from}>${e.to}`))
      lg.style.opacity = vis ? 1 : 0.15
    }
    for (const { e, g } of this.edgeEls) {
      const filtered = keep && !(keep.has(e.from) && keep.has(e.to)) ? 0.1 : 1
      g.style.opacity = filtered * (!this.focus || this.focus.edges.has(`${e.from}>${e.to}`) ? 1 : 0.12)
    }
  }

  focusArea(event) {
    const area = event.currentTarget.dataset.area
    const on = event.currentTarget.getAttribute("aria-pressed") !== "true"
    this.element.querySelectorAll("[data-action='route-map#focusArea']").forEach((b) => b.setAttribute("aria-pressed", "false"))
    if (!on) return this.highlight(null)
    event.currentTarget.setAttribute("aria-pressed", "true")
    const ids = this.map.nodes.filter((n) => n.area === area).map((n) => n.id)
    const set = new Set(ids)
    const pairs = this.map.edges.filter((e) => set.has(e.from) || set.has(e.to)).map((e) => `${e.from}>${e.to}`)
    this.map.edges.forEach((e) => { if (set.has(e.from)) set.add(e.to); if (set.has(e.to)) set.add(e.from) })
    this.highlight([...set], pairs)
  }

  // ---------- selection & planning ----------
  select(id) {
    this.openPanel()
    this.keepClearOfPanel([id])
    const n = this.byId.get(id)
    const out = this.map.edges.filter((e) => e.from === id && e.kind === "next").sort((a, b) => b.traffic - a.traffic)
    const inc = this.map.edges.filter((e) => e.to === id && e.kind === "next").sort((a, b) => b.traffic - a.traffic)
    const branches = this.map.edges.filter((e) => e.from === id && e.kind === "branch")
    const parent = this.map.edges.find((e) => e.to === id && e.kind === "branch")
    const near = new Set([id, ...out.map((e) => e.to), ...inc.map((e) => e.from), ...branches.map((e) => e.to), ...(parent ? [parent.from] : [])])
    this.highlight([...near], [...out, ...inc, ...branches, ...(parent ? [parent] : [])].map((e) => `${e.from}>${e.to}`))

    const panel = this.panelTarget
    panel.replaceChildren()
    const h = this.append(panel, "a", "font-semibold text-base text-sky-700 hover:underline", n.title)
    h.href = n.url
    this.append(panel, "div", "text-xs text-slate-500 mb-2",
      [areaName(n.area), n.kind === "unpaved" ? "unpaved: in review" : `v${n.version}`, n.improvements ? `improved ×${n.improvements}` : null, n.apps?.join(", ")].filter(Boolean).join(" · "))
    if (n.field_labels?.length) this.append(panel, "div", "text-xs text-slate-700 mb-2", `${n.field_labels.length > 1 ? "Fields" : "Field"}: ${n.field_labels.join(" · ")} ${n.classified_by === "person" ? "(✓ confirmed)" : "(✨ inferred)"}`)
    if (n.bridge) this.append(panel, "div", "text-xs font-semibold text-slate-900 mb-2", `⇄ Bridge skill: carries work ${n.bridge_label}`)
    if (n.kind === "skill") this.actionsInto(panel, [n.id], n.title)
    if (n.resources?.length) {
      this.append(panel, "h3", "font-semibold mt-3 mb-1 text-slate-700", "Resources")
      const ul = this.append(panel, "ul", "space-y-1 text-xs")
      n.resources.forEach((r) => {
        const li = this.append(ul, "li", "flex items-center gap-2")
        this.append(li, "span", "inline-grid place-items-center w-8 h-5 rounded text-[9px] font-bold text-white bg-slate-600", r.ext.toUpperCase().slice(0, 4))
        const a = this.append(li, "a", "text-sky-700 hover:underline", r.name); a.href = r.url
      })
    }
    if (n.rest_stops) {
      const rs = this.append(panel, "div", "mt-3 text-xs flex items-baseline gap-1 flex-wrap")
      this.append(rs, "span", "font-semibold text-slate-700", "🅿 Rest stops")
      this.append(rs, "span", "text-slate-500", `${n.rest_stops.count} · latest ${this.ago(n.rest_stops.latest_at)}`)
      const a = this.append(rs, "a", "text-sky-700 hover:underline ml-auto", "View or revert"); a.href = n.rest_stops.list_url
    }
    if (n.tier) {
      const box = this.append(panel, "div", "border rounded p-2 mb-2 text-xs space-y-0.5")
      this.append(box, "div", "font-semibold text-sm", this.trafficText(n))
      this.append(box, "div", "text-slate-600", `Travel time ${this.duration(n.median_minutes)} vs ${this.duration(n.freeflow_minutes)} free-flow · index ${n.index} · ${n.trips} trips`)
      if (n.bounty) this.append(box, "div", "text-slate-900", `💰 Bounty: ${this.money(n.bounty.pool)} (${n.bounty.status.replace("_", " ")}) for whoever removes the bottleneck`)
    }
    if (parent) this.list(panel, "Branched from", [parent], (e) => e.from)
    const total = out.reduce((s, e) => s + e.traffic, 0)
    this.list(panel, "Where people go next", out, (e) => e.to, (e) => this.share(e.traffic, total, e.manual))
    this.list(panel, "Where people come from", inc, (e) => e.from, (e) => this.share(e.traffic, inc.reduce((s, x) => s + x.traffic, 0), e.manual))
    if (branches.length) this.list(panel, "Branches (variants)", branches, (e) => e.to)
    if (!out.length && !inc.length && !branches.length && !parent) this.append(panel, "p", "text-slate-600", "No roads yet. When people go from this skill to another, the road appears here.")
    if (n.kind === "skill") this.directionsInto(panel, `road:${id}`)
    if (n.kind === "skill") {
      const row = this.append(panel, "div", "flex gap-1 mt-3")
      const b1 = this.append(row, "button", "px-2 py-1 rounded border bg-white hover:bg-slate-50 text-xs", "Route from here")
      b1.type = "button"; b1.addEventListener("click", () => { this.fromTarget.value = id; this.maybePlan() })
      const b2 = this.append(row, "button", "px-2 py-1 rounded border bg-white hover:bg-slate-50 text-xs", "Route to here")
      b2.type = "button"; b2.addEventListener("click", () => { this.toTarget.value = id; this.maybePlan() })
    }
  }

  duration(m) {
    if (m == null) return "—"
    if (m < 90) return `${Math.round(m)} min`
    if (m < 60 * 36) return `${Math.round(m / 6) / 10} h`
    return `${Math.round(m / 144) / 10} days`
  }

  openPanel() { this.panelTarget.classList.remove("hidden"); this.panelCloseTarget.classList.remove("hidden") }
  // Pan so the given skills sit in the part of the map the overlay panel doesn't cover.
  keepClearOfPanel(ids) {
    const pts = ids.map((i) => this.geo.positions.get(i)).filter(Boolean)
    if (!pts.length) return
    const vw = this.viewportTarget.clientWidth, pw = this.panelTarget.offsetWidth + 16
    if (!vw || pw >= vw) return
    const k = this.view.w / vw // svg units per px
    const visibleRight = this.view.x + (vw - pw) * k
    const right = Math.max(...pts.map((p) => p.x + SEG)) + 20
    if (right > visibleRight) this.setView({ ...this.view, x: this.view.x + (right - visibleRight) })
  }
  closePanel() { this.panelTarget.classList.add("hidden"); this.panelCloseTarget.classList.add("hidden"); this.highlight(null) }

  // ---------- send to an add-in / agent ----------
  actionsInto(panel, names, title) {
    const box = this.append(panel, "div", "border rounded p-2 my-2 space-y-2 bg-slate-50")
    const row = this.append(box, "div", "flex flex-wrap gap-1")
    if (names.length === 1) {
      const open = this.append(row, "a", "px-2 py-1 rounded border bg-white text-xs hover:bg-slate-50", "Open skill")
      open.href = this.byId.get(names[0])?.url || "#"
    }
    const mine = this.append(row, "button", "px-2 py-1 rounded bg-slate-900 text-white text-xs hover:bg-slate-700",
      names.length > 1 ? `Send route (${names.length}) to my add-in` : "Send to my add-in")
    mine.type = "button"
    mine.addEventListener("click", () => this.send(names, "me", status))
    const route = this.append(box, "div", "flex gap-1")
    const sel = this.append(route, "select", "border rounded px-1 py-1 text-xs flex-1 min-w-0")
    sel.setAttribute("aria-label", "Send to")
    this.append(sel, "option", null, "Route to…").value = ""
    this.recipientsValue.filter(([, v]) => v !== "me").forEach(([label, v]) => { const o = this.append(sel, "option", null, label); o.value = v })
    const go = this.append(route, "button", "px-2 py-1 rounded border bg-white text-xs", "Send")
    go.type = "button"
    go.addEventListener("click", () => sel.value && this.send(names, sel.value, status))
    const status = this.append(box, "p", "text-xs text-slate-600", "Loads the skill, its directions and resources into the add-in's memory.")
  }

  async send(names, target, status) {
    status.textContent = "Sending…"
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    const body = new URLSearchParams()
    names.forEach((n) => body.append("skills[]", n))
    body.set("target", target)
    const res = await fetch(this.sendUrlValue, { method: "POST", headers: { "X-CSRF-Token": token, Accept: "application/json" }, body })
    const r = await res.json()
    if (!res.ok) { status.textContent = r.error || "Couldn't send"; return }
    status.textContent = `Queued for ${r.to}. Waiting for it to check in…`
    this.watchDelivery(r.id, status)
  }

  watchDelivery(id, status, tries = 0) {
    clearTimeout(this.deliveryTimer)
    this.deliveryTimer = setTimeout(async () => {
      const res = await fetch(`${this.sentUrlValue}?ids[]=${id}`, { headers: { Accept: "application/json" } })
      const [c] = await res.json()
      if (c?.status === "delivered") status.textContent = `✓ Delivered to ${c.to} (${c.delivered_to}): now in its memory.`
      else if (tries < 40) this.watchDelivery(id, status, tries + 1)
      else status.textContent = `Still queued for ${c?.to}. It will arrive when the add-in is next open (within a day).`
    }, 3000)
  }

  // ---------- places & directions ----------
  async directionsInto(container, key, { open = true } = {}) {
    const box = this.append(container, "div", "mt-3 border-t pt-2")
    const head = this.append(box, "div", "flex items-baseline justify-between gap-2")
    this.append(head, "h3", "font-semibold text-slate-700", "Agent directions")
    const status = this.append(box, "p", "text-xs text-slate-500", "Loading…")
    try {
      const res = await fetch(`${this.placeUrlValue}${encodeURIComponent(key)}.json`, { headers: { Accept: "application/json" } })
      const p = await res.json()
      if (!res.ok) throw new Error(p.error || "Not found")
      status.textContent = p.written ? `Written · v${p.version}${p.updated_by ? ` · ${p.updated_by}` : ""}` : "Generated from live data (not written yet)"
      const links = this.append(head, "span", "text-xs whitespace-nowrap")
      const a = this.append(links, "a", "text-sky-700 hover:underline", p.editable ? (p.written ? "Edit" : "Write") : "Open")
      a.href = p.editable ? `${p.url}/edit` : p.url
      const md = this.append(links, "a", "text-sky-700 hover:underline ml-2", ".md")
      md.href = `${p.url}.md`
      const art = this.append(box, "article", "text-xs leading-relaxed mt-1 max-h-96 overflow-auto")
      art.innerHTML = renderMarkdown(p.markdown)
      if (!open) art.classList.add("hidden")
    } catch (e) { status.textContent = e.message }
  }

  selectJunction(id) {
    this.openPanel()
    const n = this.byId.get(id)
    const out = this.map.edges.filter((e) => e.from === id && e.kind === "next").sort((a, b) => b.traffic - a.traffic)
    this.highlight([id, ...out.map((e) => e.to)], out.map((e) => `${e.from}>${e.to}`))
    const panel = this.panelTarget
    panel.replaceChildren()
    this.append(panel, "div", "text-xs text-slate-500", "Intersection")
    this.append(panel, "h2", "font-semibold text-base", `After ${n.title}`)
    this.list(panel, "Exits", out, (e) => e.to, (e) => this.share(e.traffic, out.reduce((s, x) => s + x.traffic, 0), e.manual))
    this.directionsInto(panel, `junction:${id}`)
    this.centerOn(id)
  }

  selectHandoff(from, to) {
    this.openPanel()
    this.keepClearOfPanel([from, to])
    const a = this.byId.get(from), b = this.byId.get(to)
    const e = this.map.edges.find((x) => x.from === from && x.to === to && x.kind === "next")
    this.highlight([from, to], [`${from}>${to}`])
    const panel = this.panelTarget
    panel.replaceChildren()
    this.append(panel, "div", "text-xs text-slate-500", e?.bridge ? `⇄ Bridge · ${this.bridgeText(e.bridge)}` : "Handoff")
    this.append(panel, "h2", "font-semibold text-base", `${a.title} → ${b.title}`)
    this.append(panel, "p", "text-xs text-slate-600", e?.traffic ? `${e.traffic} trips` : "Linked by a reviewer")
    this.directionsInto(panel, `handoff:${from}>${to}`)
  }

  centerOn(id) {
    const p = this.geo.positions.get(id)
    if (!p || !this.view) return
    this.setView({ ...this.view, x: p.x + SEG / 2 - this.view.w / 2, y: p.y - this.view.h / 3 })
  }

  focusPlace(key) {
    const [kind, rest] = key.split(/:(.*)/s)
    this.resultsTarget.hidden = true
    if (kind === "road") { this.select(rest); this.centerOn(rest) }
    else if (kind === "junction") this.selectJunction(rest)
    else if (kind === "handoff") { const [a, b] = rest.split(">"); this.selectHandoff(a, b); this.centerOn(a) }
  }

  searchInput() {
    clearTimeout(this.searchTimer)
    const q = this.searchTarget.value.trim()
    if (q.length < 2) { this.resultsTarget.hidden = true; return }
    this.searchTimer = setTimeout(() => this.runSearch(q), 180)
  }

  async runSearch(q) {
    const res = await fetch(`${this.searchUrlValue}?q=${encodeURIComponent(q)}`, { headers: { Accept: "application/json" } })
    const hits = await res.json()
    if (q !== this.searchTarget.value.trim()) return
    const box = this.resultsTarget
    box.replaceChildren()
    if (!hits.length) this.append(box, "p", "p-3 text-slate-500", `Nothing on the map matches “${q}”.`)
    hits.forEach((h) => {
      const b = this.append(box, "button", "w-full text-left flex items-baseline gap-3 px-3 py-2 hover:bg-slate-50 focus:bg-slate-100")
      b.type = "button"; b.setAttribute("role", "option")
      this.append(b, "span", "w-20 shrink-0 text-xs text-slate-500", h.label)
      const t = this.append(b, "span", "flex-1", h.title)
      this.append(t, "span", "text-xs text-slate-500 ml-2", h.subtitle || "")
      this.append(b, "span", `text-xs ${h.written ? "text-slate-700" : "text-slate-400"}`, h.written ? "Written" : "Generated")
      b.addEventListener("click", () => this.focusPlace(h.key))
    })
    box.hidden = false
  }

  searchKey(ev) {
    if (ev.key === "Escape") this.resultsTarget.hidden = true
    if (ev.key === "ArrowDown") { ev.preventDefault(); this.resultsTarget.querySelector("button")?.focus() }
    if (ev.key === "Enter") { ev.preventDefault(); this.resultsTarget.querySelector("button")?.click() }
  }

  share(traffic, total, manual) {
    if (!traffic) return manual ? "linked by a reviewer" : ""
    return `${traffic} trip${traffic === 1 ? "" : "s"}${total ? ` · ${Math.round((traffic * 100) / total)}%` : ""}${manual ? " · confirmed by a reviewer" : ""}`
  }

  list(panel, heading, edges, keyOf, note) {
    if (!edges.length) return
    this.append(panel, "h3", "font-semibold mt-3 mb-1 text-slate-700", heading)
    const ul = this.append(panel, "ul", "space-y-1")
    edges.forEach((e) => {
      const target = this.byId.get(keyOf(e))
      const li = this.append(ul, "li", "")
      const b = this.append(li, "button", "text-left text-sky-700 hover:underline", target.title)
      b.type = "button"; b.addEventListener("click", () => this.select(target.id))
      const text = note ? note(e) : ""
      if (text) this.append(li, "div", "text-xs text-slate-500", text)
    })
  }

  maybePlan() { if (this.fromTarget.value && this.toTarget.value) this.plan() }

  async plan(event) {
    event?.preventDefault()
    const from = this.fromTarget.value, to = this.toTarget.value
    if (!from || !to) return
    const res = await fetch(`${this.routeUrlValue}?from=${encodeURIComponent(from)}&to=${encodeURIComponent(to)}`, { headers: { Accept: "application/json" } })
    const r = await res.json()
    const panel = this.panelTarget
    panel.replaceChildren()
    this.openPanel()
    this.append(panel, "h2", "font-semibold mb-2", "Route")
    if (!r.found) {
      this.highlight([from, to], [])
      this.append(panel, "p", "text-slate-700", `No known road from “${this.byId.get(from).title}” to “${this.byId.get(to).title}” yet.`)
      this.append(panel, "p", "text-slate-500 mt-1", "That's a gap: if people do get from one to the other, record the steps in between so the next person can follow them.")
      return
    }
    this.highlight(r.keys, r.legs.map((l) => `${l.from}>${l.to}`))
    const ol = this.append(panel, "ol", "space-y-2")
    r.stops.forEach((s, i) => {
      const li = this.append(ol, "li", "flex gap-2")
      this.append(li, "span", "shrink-0 grid place-items-center w-6 h-6 rounded-full bg-slate-900 text-white text-xs", String(i + 1))
      const body = this.append(li, "div", "")
      this.append(body, "div", "text-xs text-slate-500", i === 0 ? "Start" : i === r.stops.length - 1 ? "Arrive" : "Then")
      const a = this.append(body, "a", "text-sky-700 hover:underline", s.title)
      a.href = s.url
      this.append(body, "div", "text-xs text-slate-500", [areaName(s.area), s.apps?.join(", "), `${s.steps} steps`].filter(Boolean).join(" · "))
      if (s.tier) this.append(body, "div", "text-xs text-slate-700", this.trafficText(s))
      const leg = r.legs[i]
      if (leg) this.append(body, "div", "text-xs text-slate-400 mt-1", leg.traffic ? `↓ ${leg.traffic} people took this road` : "↓ linked by a reviewer")
    })
    this.actionsInto(panel, r.keys.filter((k) => !k.startsWith("candidate:")), "route")
    if (r.directions?.length) {
      this.append(panel, "h3", "font-semibold mt-4 mb-1 text-slate-700", "Agent directions, in order")
      const ul = this.append(panel, "ol", "list-decimal ml-5 space-y-0.5 text-xs")
      r.directions.forEach((d) => {
        const li = this.append(ul, "li", "")
        const a = this.append(li, "a", "text-sky-700 hover:underline", d.title)
        a.href = d.url
        if (!d.written) this.append(li, "span", "text-slate-400 ml-1", "(generated)")
      })
    }
  }

  clear() {
    this.fromTarget.value = ""; this.toTarget.value = ""
    this.closePanel()
  }

  append(parent, tag, cls, text) {
    const e = document.createElement(tag)
    if (cls) e.className = cls
    if (text != null) e.textContent = text
    parent.appendChild(e)
    return e
  }

  // ---------- tooltips ----------
  nodeTip(ev, n) {
    const stage = { local: "Local (sandbox)", firm: "Firm", market: "Market" }[n.stage]
    const lines = [[n.title, "font-semibold"], [[areaName(n.area), n.kind === "unpaved" ? "unpaved: in review" : `v${n.version}`, stage].filter(Boolean).join(" · "), "text-slate-600"],
      ...(n.bridge ? [[`⇄ Bridge: ${n.bridge_label}`, "font-semibold"]] : []),
      ...(n.field_labels?.length ? [[`${n.field_labels.length > 1 ? "Fields" : "Field"}: ${n.field_labels.join(" · ")}${n.classified_by === "person" ? " ✓" : " ✨"}`, "text-slate-700"]] : []),
      ...(n.tier ? [[this.trafficText(n), "text-slate-900"]] : []),
      ...(n.bounty ? [[`💰 Bounty ${this.money(n.bounty.pool)}`, "text-slate-900"]] : []),
      [[n.apps?.join(", "), `${n.steps} steps`, n.improvements ? `improved ×${n.improvements}` : null, n.contributors ? `${n.contributors} contributors` : null].filter(Boolean).join(" · "), "text-slate-600"]]
    this.showTip(ev, lines)
  }

  // Map label: the app hop if there is one (the most concrete crossing), else the field hop.
  bridgeShort(b) { return (b.apps || b.fields || []).join(" → ") }

  ago(iso) {
    const m = Math.max(0, (Date.now() - Date.parse(iso)) / 60000)
    return m < 1 ? "just now" : m < 60 ? `${Math.round(m)} min ago` : m < 1440 ? `${Math.round(m / 60)} h ago` : `${Math.round(m / 1440)} d ago`
  }

  bridgeText(b) {
    return [b.fields ? b.fields.join(" → ") : null, b.apps ? b.apps.join(" → ") : null].filter(Boolean).join(" · ")
  }

  edgeTip(ev, e) {
    const a = this.byId.get(e.from).title, b = this.byId.get(e.to).title
    const head = e.kind === "branch" ? "Branch (variant)" : e.traffic ? `${e.traffic} trip${e.traffic === 1 ? "" : "s"}` : "Linked by a reviewer"
    this.showTip(ev, [[e.bridge ? `⇄ Bridge: ${this.bridgeText(e.bridge)}` : head, "font-semibold"], ...(e.bridge ? [[head, "text-slate-600"]] : []), [`${a} → ${b}`, "text-slate-600"]])
  }

  showTip(ev, lines) {
    const tip = this.tipTarget
    tip.replaceChildren()
    lines.forEach(([t, c]) => this.append(tip, "div", c, t))
    tip.hidden = false
    this.moveTip(ev)
  }

  moveTip(ev) {
    const tip = this.tipTarget, box = this.viewportTarget.getBoundingClientRect()
    let x, y
    if (ev.type === "focus") { const r = ev.currentTarget.getBoundingClientRect(); x = r.left - box.left; y = r.bottom - box.top + 4 }
    else { x = ev.clientX - box.left + 14; y = ev.clientY - box.top + 14 }
    tip.style.left = `${Math.max(4, Math.min(x, box.width - tip.offsetWidth - 4))}px`
    tip.style.top = `${Math.min(y, box.height - tip.offsetHeight - 4)}px`
  }

  hideTip() { this.tipTarget.hidden = true }

  // ---------- pan & zoom (viewBox) ----------
  setView(v) { this.view = v; this.svgTarget.setAttribute("viewBox", `${v.x} ${v.y} ${v.w} ${v.h}`) }

  // Height follows the content at full width (no empty band), within sensible limits.
  // Below this the labels are unreadable, so small screens pan instead of shrinking.
  static MIN_SCALE = 0.62

  scale() {
    const width = this.viewportTarget.getBoundingClientRect().width || 800
    return Math.max(this.constructor.MIN_SCALE, Math.min(1.15, width / Math.max(this.geo.width, 400)))
  }

  sizeViewport() {
    const vp = this.viewportTarget
    const wanted = this.geo.height * this.scale() + 8
    vp.style.height = `${Math.round(Math.max(320, Math.min(wanted, window.innerHeight * 0.75)))}px`
  }

  fit() {
    const box = this.viewportTarget.getBoundingClientRect()
    const k = this.scale()
    const w = (box.width || 800) / k, h = (box.height || 500) / k
    // Whole map when it fits; otherwise start at the beginning of the roads (left, top).
    const x = w >= this.geo.width ? (this.geo.width - w) / 2 : 0
    this.setView({ x, y: 0, w, h })
  }

  zoomBy(factor, cx = 0.5, cy = 0.5) {
    const v = this.view
    const w = Math.min(Math.max(v.w * factor, 200), Math.max(this.geo.width, 400) * 4)
    const h = w * (v.h / v.w)
    this.setView({ x: v.x + (v.w - w) * cx, y: v.y + (v.h - h) * cy, w, h })
  }

  zoomIn() { this.zoomBy(0.8) }
  zoomOut() { this.zoomBy(1.25) }

  wheel(ev) {
    ev.preventDefault()
    const box = this.viewportTarget.getBoundingClientRect()
    this.zoomBy(ev.deltaY > 0 ? 1.1 : 0.9, (ev.clientX - box.left) / box.width, (ev.clientY - box.top) / box.height)
  }

  panStart(ev) {
    if (ev.target.closest(".rm-node")) return
    this.drag = { x: ev.clientX, y: ev.clientY, view: { ...this.view } }
    this.viewportTarget.setPointerCapture?.(ev.pointerId)
  }

  panMove(ev) {
    if (!this.drag) return
    const box = this.viewportTarget.getBoundingClientRect()
    const k = this.view.w / box.width
    this.setView({ ...this.drag.view, x: this.drag.view.x - (ev.clientX - this.drag.x) * k, y: this.drag.view.y - (ev.clientY - this.drag.y) * k })
  }

  panEnd() { this.drag = null }
}
