import { Controller } from "@hotwired/stimulus"
import { layout, roadPath, branchPath, branchJunction, trafficWidth, DEFAULTS } from "route_map/layout"

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
const areaName = (a) => (!a ? "No area" : a.length <= 3 ? a.toUpperCase() : a.split(/[-_\s]+/).map((w) => w[0].toUpperCase() + w.slice(1)).join(" "))

// The route map: skills as road segments, journeys as roads between them,
// branches as side roads, unpublished workflows as unpaved roads.
export default class extends Controller {
  static targets = ["data", "svg", "viewport", "tip", "panel", "from", "to", "modeBtn", "areaLegend", "trafficLegend"]
  static values = { routeUrl: String, colors: Object, tiers: Object, currency: String }

  connect() {
    this.map = JSON.parse(this.dataTarget.textContent)
    this.byId = new Map(this.map.nodes.map((n) => [n.id, n]))
    this.geo = layout(this.map.nodes, this.map.edges)
    this.maxTraffic = Math.max(1, ...this.map.edges.map((e) => e.traffic || 0))
    this.focus = null
    this.mode = "area"
    this.draw()
    this.sizeViewport()
    this.fit()
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
        el("path", { d, fill: "none", stroke: SURFACE, "stroke-width": w + 4, "stroke-linecap": "round" }, g)
        el("path", { d, fill: "none", stroke: e.traffic ? ROAD : ROAD_LINKED, "stroke-width": w, "stroke-linecap": "round" }, g)
        el("path", { d, fill: "none", stroke: "transparent", "stroke-width": 1, "marker-end": "url(#rm-arrow)" }, g)
        el("path", { d, fill: "none", stroke: "transparent", "stroke-width": Math.max(14, w + 6) }, g)
      }
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
      el("line", { x1: 0, y1: 0, x2: SEG, y2: 0, stroke: SURFACE, "stroke-width": 14, "stroke-linecap": "round" }, g)
      el("line", { x1: 0, y1: 0, x2: SEG, y2: 0, stroke: c, "stroke-width": 10, "stroke-linecap": "round",
        "stroke-dasharray": n.kind === "unpaved" ? "12 9" : null }, g)
      for (const x of [0, SEG]) el("circle", { cx: x, cy: 0, r: 5, fill: "#ffffff", stroke: c, "stroke-width": 3 }, g)
      const title = el("text", { x: 0, y: -15, "font-size": 15, "font-weight": 600, fill: INK }, g)
      title.textContent = truncate(n.title, 26)
      const meta = this.mode === "traffic" && n.tier
        ? [`${this.tiersValue[n.tier].icon} ${this.tiersValue[n.tier].label}`, this.money(n.price), n.bounty ? `💰 ${this.money(n.bounty.pool)}` : null].filter(Boolean).join(" · ")
        : [n.apps?.join(", "), `${n.steps} steps`, n.kind === "unpaved" ? "unpaved" : null,
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
  }

  // ---------- highlight ----------
  highlight(nodeIds, edgePairs) {
    this.focus = nodeIds ? { nodes: new Set(nodeIds), edges: new Set(edgePairs || []) } : null
    for (const [id, g] of this.nodeEls) g.style.opacity = !this.focus || this.focus.nodes.has(id) ? 1 : 0.18
    for (const { e, g } of this.edgeEls) {
      g.style.opacity = !this.focus || this.focus.edges.has(`${e.from}>${e.to}`) ? 1 : 0.12
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
  }

  clear() {
    this.fromTarget.value = ""; this.toTarget.value = ""
    this.highlight(null)
    this.panelTarget.replaceChildren()
    this.append(this.panelTarget, "h2", "font-semibold mb-1", "Plan a route")
    this.append(this.panelTarget, "p", "text-slate-600", "Pick where you are and where you need to get to, or click a skill on the map to see where people go next.")
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
    const lines = [[n.title, "font-semibold"], [[areaName(n.area), n.kind === "unpaved" ? "unpaved: in review" : `v${n.version}`].join(" · "), "text-slate-600"],
      ...(n.tier ? [[this.trafficText(n), "text-slate-900"]] : []),
      ...(n.bounty ? [[`💰 Bounty ${this.money(n.bounty.pool)}`, "text-slate-900"]] : []),
      [[n.apps?.join(", "), `${n.steps} steps`, n.improvements ? `improved ×${n.improvements}` : null, n.contributors ? `${n.contributors} contributors` : null].filter(Boolean).join(" · "), "text-slate-600"]]
    this.showTip(ev, lines)
  }

  edgeTip(ev, e) {
    const a = this.byId.get(e.from).title, b = this.byId.get(e.to).title
    const head = e.kind === "branch" ? "Branch (variant)" : e.traffic ? `${e.traffic} trip${e.traffic === 1 ? "" : "s"}` : "Linked by a reviewer"
    this.showTip(ev, [[head, "font-semibold"], [`${a} → ${b}`, "text-slate-600"]])
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
