import { createApi, settings } from "addin/api";
import { createCapture } from "addin/capture";
import { manualStep } from "addin/vocabulary";
import { wireHost, setAutoLoad, insertText, openInBrowser, connectDialog } from "addin/office_hosts";
import { renderMarkdown, toPlainSteps } from "addin/markdown";
import { memory } from "addin/memory";
import { registerRibbon, showPane } from "addin/ribbon";
import { plan as planSheet, apply as applySheet, colLetter } from "addin/worksheet_builder";
import { observeCells } from "addin/sheet_capture";
import { createFlowPane } from "addin/flow_pane";

const root = document.getElementById("app");
const view = document.getElementById("view");
const api = createApi();
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const CAPTURE_KEY = "skillcapture.capturing";
const DRAFT_KEY = "skillcapture.recordingDraft"; // autosaved recording (redundancy if the pane closes)
const areaName = (n) => n === "factset" ? "FactSet" : n.length <= 3 ? n.toUpperCase() : n.split(/[-_\s]+/).map((w) => w[0].toUpperCase() + w.slice(1)).join(" ");

const state = { host: null, me: null, tab: "library", capture: null, wired: null, flash: null, flashKind: "ok", prompts: [], recovered: null,
                hostOnly: settings.get("skillcapture.hostOnly") !== "0", // default: show skills for the app you're in
                area: settings.get("skillcapture.area") || "", level: settings.get("skillcapture.level") || "" };
const LEVELS = [["", "All"], ["mine", "Mine"], ["received", "Sent to me"], ["department", "Department"], ["firm", "Firm"], ["industry", "Industry"], ["global", "Global"]];
let flushTimer = null;
let flows = null; // created once the helpers below exist

const btn = "inline-flex items-center justify-center px-3 py-1.5 rounded border bg-white hover:bg-slate-50";
const btnPrimary = "inline-flex items-center justify-center px-3 py-1.5 rounded bg-slate-900 text-white hover:bg-slate-700";
const input = "border rounded px-2 py-1.5 w-full";

function flash(message, kind = "ok") { state.flash = message; state.flashKind = kind; }
function flashHtml() {
  if (!state.flash) return "";
  const cls = state.flashKind === "error" ? "bg-red-50 border-red-200 text-red-900" : "bg-emerald-50 border-emerald-200 text-emerald-900";
  const html = `<div class="mb-3 rounded border px-2 py-1.5 ${cls}">${esc(state.flash)}</div>`;
  state.flash = null;
  return html;
}

const stageLabel = (st) => ({ local: "🧪 Local (sandbox)", firm: "🏢 Firm", market: "🌐 Market" }[st] || "");
function voteHtml(s) {
  const v = s.votes || { score: 0, up: 0, down: 0 };
  const btnCls = (on) => `px-2 py-0.5 rounded border ${on ? "bg-slate-900 text-white" : "bg-white"}`;
  return `<span class="font-semibold tabular-nums">${v.score > 0 ? "+" : ""}${v.score}</span>
    <span class="text-xs text-slate-500">${v.up} for · ${v.down} against</span>
    ${s.can_vote ? `<button data-action="vote" data-value="${s.my_vote === 1 ? 0 : 1}" aria-pressed="${s.my_vote === 1}" class="${btnCls(s.my_vote === 1)}">👍 Better</button>
      <button data-action="vote" data-value="${s.my_vote === -1 ? 0 : -1}" aria-pressed="${s.my_vote === -1}" class="${btnCls(s.my_vote === -1)}" aria-label="Needs work">👎</button>` : ""}`;
}

// Traffic tiers wear the fixed status colors, always with an icon and a label.
const STATUS = [["#0ca30c", "●"], ["#fab219", "▲"], ["#ec835a", "▲"], ["#d03b3b", "■"]];
function trafficHtml(s) {
  const t = s.traffic;
  const [color, icon] = STATUS[t.tiers <= 1 ? 0 : Math.round((t.rank * (STATUS.length - 1)) / (t.tiers - 1))];
  const money = (v) => `${Math.round(v * 100) / 100} ${esc(t.currency)}`;
  return `<div class="border rounded p-2 mb-2">
    <div><span style="color:${color}" aria-hidden="true">${icon}</span> <strong>${esc(t.label)} traffic</strong> · ${money(t.price)} per trip</div>
    ${t.bounty ? `<div class="mt-1">💰 ${money(t.bounty.pool)} bounty for whoever removes this bottleneck.
      ${t.bounty.status === "open" ? `<button data-action="open-url" data-url="${esc(s.fix_url)}" class="text-sky-700 hover:underline">Propose a faster way</button>` : `<span class="text-slate-500">(${esc(t.bounty.status.replace("_", " "))})</span>`}</div>` : ""}
  </div>`;
}

// ---------- boot ----------
async function boot() {
  const info = window.Office?.onReady ? await Office.onReady() : { host: null };
  state.host = info.host ? String(info.host) : null;
  document.getElementById("host-label").textContent = state.host || "Not in Office";

  state.capture = createCapture({ host: state.host, send: (p) => api.sendEvents(p) });
  state.capture.onChange(() => {
    if (state.tab === "record") renderRecordSteps();
    updateCaptureBadge();
    const rec = state.capture.state().recording;
    if (rec) settings.set(DRAFT_KEY, JSON.stringify({ steps: rec.steps, savedAt: Date.now() }));
  });
  try {
    const draft = JSON.parse(settings.get(DRAFT_KEY) || "null");
    if (draft?.steps?.length) state.recovered = draft;
  } catch { settings.set(DRAFT_KEY, null); }

  if (state.host && ["Excel", "Word", "PowerPoint"].includes(state.host)) {
    try { state.wired = await wireHost(state.host, (k) => state.capture.record(k)); }
    catch (e) { state.wired = { supported: false, error: e.message, events: {} }; }
  }
  await loadMe();
  render();
  wireRibbon();
}

// ---------- the "Skill Capture" ribbon tab ----------
function wireRibbon() {
  const go = async (tab, message) => {
    await showPane(window.Office);
    if (tab === "review" && !state.me?.reviewer) { tab = "library"; message = "Review is for reviewers; here's the library."; }
    state.tab = tab;
    if (message) flash(message);
    render();
  };
  const web = (path) => () => openInBrowser(`${state.me?.console_url?.replace(/\/$/, "") || location.origin}${typeof path === "function" ? path() : path}`);
  const scoped = (base, extra = {}) => () => {
    const q = new URLSearchParams(extra);
    if (state.area) q.set(base === "/map" ? "area" : "domain", state.area);
    if (state.level) q.set("level", state.level);
    if (base === "/map" && (state.area || state.level)) q.set("hide", "1");
    return `${base}${q.toString() ? `?${q}` : ""}`;
  };
  registerRibbon(window.Office, {
    showMemory: () => go("memory"),
    showRecord: () => go("record"),
    showReview: () => go("review"),
    startRecording: async () => {
      await go("record");
      if (!state.me) return;
      if (!state.host) { flash("Recording works inside Excel, Word or PowerPoint.", "error"); return render(); }
      if (!state.capture.state().recording) { state.capture.startRecording(); renderRecord(); updateCaptureBadge(); }
    },
    toggleCapture: async () => {
      if (!state.me) return go("library");
      const on = !state.capture.state().capturing;
      settings.set(CAPTURE_KEY, on ? "on" : "off");
      state.capture.setCapturing(on && !!state.host);
      try { await setAutoLoad(on); } catch { /* not supported on this client */ }
      await go(state.tab, on ? "Capture is on: Skill Capture notes step types (never document content)." : "Capture is off.");
    },
    focusSearch: async () => { await go("library"); setTimeout(() => document.querySelector('input[name="q"]')?.focus(), 50); },
    captureSheet: async () => { await go("record"); await captureActiveSheet(); },
    openMap: web(scoped("/map")),
    openLibrary: web(scoped("/skills")),
    openReturns: web("/playbooks"),
    openConsole: web("/"),
  });
}

async function loadMe() {
  if (!api.connected) { state.me = null; return; }
  try {
    state.me = await api.me();
    const wants = settings.get(CAPTURE_KEY) === "on" && state.me.capture_enabled;
    state.capture.setCapturing(wants && !!state.host);
    state.capture.setDomain(state.me.domains?.[0]);
    clearInterval(flushTimer);
    flushTimer = setInterval(() => state.capture.flush().catch(() => {}), 15000);
    startInbox();
  } catch (e) {
    state.me = null;
    if (e.status !== 401) flash(e.message, "error");
  }
}

// ---------- skills sent from the map → local memory ----------
let inboxTimer = null;
function startInbox() {
  clearInterval(inboxTimer);
  checkInbox();
  inboxTimer = setInterval(checkInbox, 5000);
}

let inboxTicks = 0;

async function checkInbox() {
  if (!api.connected) return;
  if (inboxTicks++ % 6 === 0) { // prompts every 30 s
    try {
      const before = state.prompts.map((p) => p.id).join();
      state.prompts = await api.prompts();
      if (state.prompts.map((p) => p.id).join() !== before) renderPromptCard();
    } catch { /* offline */ }
  }
  try {
    let cmds = await api.commands(state.host, window.Office?.context?.diagnostics?.platform);
    if (!cmds.length) return;
    const task = cmds.find((c) => c.kind === "flow_task")?.task;
    if (task) {
      flash(`Your turn: ${task.title} (task ${task.step_index + 1} in “${task.flow}”)${task.previous ? `, handed off by ${task.previous.by}` : ""}.`);
      await flowPane().showTask(task).catch(() => {});
      state.tab = "flows";
    }
    cmds.filter((c) => c.kind === "flow_task").forEach((c) => (c.bundles || []).forEach((b) => memory.add(b, c.from)));
    cmds = cmds.filter((c) => c.kind !== "flow_task");
    if (!cmds.length) return render();
    let added = 0;
    const names = [];
    cmds.forEach((c) => c.bundles.forEach((b) => { memory.add(b, c.from); added++; names.push(b.title); }));
    const from = cmds[0].from;
    flash(`${from ? `${from} sent` : "Received"} ${added === 1 ? `“${names[0]}”` : `${added} skills`}. Added to memory.`);
    state.tab = "memory";
    render();
  } catch { /* offline: try again next tick */ }
}

// ---------- rendering ----------
function render() {
  if (!state.me) return renderConnect();
  const tabs = [["library", "Library"], ["flows", "Flows"], ["memory", `Memory${memory.list().length ? ` (${memory.list().length})` : ""}`], ["record", "Record"]];
  if (state.me.reviewer) tabs.push(["review", `Review${state.me.open_reviews ? ` (${state.me.open_reviews})` : ""}`]);
  tabs.push(["settings", "Settings"]);
  view.innerHTML = `
    <div class="flex justify-end -mt-1 mb-1"><span id="capture-badge" class="text-xs"></span></div>
    <nav class="flex mb-3 border-b overflow-x-auto" role="tablist">
      ${tabs.map(([id, label]) => `<button role="tab" data-tab="${id}" aria-selected="${state.tab === id}"
         class="px-2 py-1.5 -mb-px border-b-2 whitespace-nowrap ${state.tab === id ? "border-slate-900 font-semibold" : "border-transparent text-slate-500"}">${esc(label)}</button>`).join("")}
    </nav>
    ${flashHtml()}
    <div id="prompt-card"></div>
    <section id="panel"></section>`;
  renderPromptCard();
  updateCaptureBadge();
  ({ library: renderLibrary, flows: () => flowPane().render(), memory: renderMemory, record: renderRecord, review: renderReview, settings: renderSettings }[state.tab])();
}

// ---------- save / extend / branch prompts ----------
const CHOICE = { save: "💾 Save as a skill", extend: "➕ Extend", branch: "⑂ Branch" };
const KIND_ICON = { save: "💾", extend: "➕", branch: "⑂" };
function renderPromptCard() {
  const el = document.getElementById("prompt-card");
  if (!el) return;
  const p = state.prompts[0];
  if (!p) { el.innerHTML = ""; return; }
  const added = new Set(p.added);
  const naming = p.choices.includes("save") || p.choices.includes("branch");
  el.innerHTML = `
    <div class="mb-3 rounded border border-amber-300 bg-amber-50 p-2" role="region" aria-label="Suggestion">
      <div class="flex gap-1.5"><span aria-hidden="true">${KIND_ICON[p.kind]}</span><strong class="flex-1">${esc(p.headline)}</strong>
        ${state.prompts.length > 1 ? `<span class="text-xs text-slate-500 whitespace-nowrap">1 of ${state.prompts.length}</span>` : ""}</div>
      <ol class="list-decimal ml-5 mt-1 text-xs">${p.steps.map((s) => `<li class="${added.has(s.label) ? "text-emerald-800 font-semibold" : "text-slate-600"}">${esc(s.label)}${added.has(s.label) ? " (new)" : ""}</li>`).join("")}</ol>
      ${p.removed.length ? `<div class="text-xs text-red-700 mt-1">You skip: ${p.removed.map(esc).join(", ")}</div>` : ""}
      ${p.why ? `<div class="text-xs text-slate-600 mt-1">${p.evaluated_by === "ai" ? "✨ " : ""}${esc(p.why)}</div>` : ""}
      ${naming ? `<input id="prompt-title" value="${p.kind === "extend" ? "" : esc(p.suggested_title || "")}" class="${input} mt-2 text-xs" placeholder="${p.kind === "save" ? "Name it (optional)" : `${esc(p.skill_title || "")} (my way)`}" aria-label="Name">` : ""}
      <div class="flex flex-wrap gap-1 mt-2">
        ${p.choices.map((c, i) => `<button data-action="prompt" data-id="${p.id}" data-choice="${c}" class="${i ? btn : btnPrimary} text-xs">${CHOICE[c]}</button>`).join("")}
        <button data-action="prompt" data-id="${p.id}" data-choice="snooze" class="${btn} text-xs">Not now</button>
        <button data-action="prompt" data-id="${p.id}" data-choice="dismiss" class="text-xs text-slate-500 hover:underline px-1">Don't ask again</button>
      </div>
    </div>`;
}

function updateCaptureBadge() {
  const el = document.getElementById("capture-badge");
  if (!el || !state.capture) return;
  const s = state.capture.state();
  el.innerHTML = s.recording ? '<span class="text-red-600">● Recording</span>'
    : s.capturing ? '<span class="text-emerald-700">● Capturing</span>' : '<span class="text-slate-400">Capture off</span>';
}

function renderConnect() {
  view.innerHTML = `
    ${flashHtml()}
    <div class="space-y-3">
      <h1 class="text-base font-semibold">Your team's procedures, inside Office</h1>
      <ul class="list-disc ml-5 text-slate-600 space-y-1">
        <li>Find and follow skills your colleagues have captured.</li>
        <li>Record how you do a task so others can reuse it.</li>
        <li>Review and publish captured workflows if you're a reviewer.</li>
      </ul>
      <button data-action="connect" class="${btnPrimary} w-full">Sign in to Skill Capture</button>
      ${state.host ? "" : '<p class="text-xs text-slate-500">Open this pane from the Skills button in Excel, Word or PowerPoint.</p>'}
    </div>`;
}

const panel = () => document.getElementById("panel");

async function renderLibrary(q = state.query || "", area = state.area || "") {
  state.query = q; state.area = area;
  settings.set("skillcapture.area", area || null);
  panel().innerHTML = `
    <div id="offers"></div>
    <form data-form="search" class="flex gap-1 mb-2">
      <input name="q" value="${esc(q)}" placeholder="Search ${area ? `${esc(areaName(area))} ` : ""}skills" class="${input}" aria-label="Search skills">
      <button class="${btn}">Search</button>
    </form>
    <div class="flex flex-wrap gap-1 mb-2 text-xs" role="group" aria-label="Level">
      ${LEVELS.map(([v, l]) => `<button data-action="set-level" data-level="${v}" aria-pressed="${state.level === v}" class="px-2 py-0.5 rounded border ${state.level === v ? "bg-sky-700 text-white border-sky-700" : "bg-white"}">${l}</button>`).join("")}
    </div>
    ${state.host ? `<label class="flex items-center gap-1.5 text-xs mb-2"><input type="checkbox" data-action="host-only" ${state.hostOnly ? "checked" : ""}> Only ${esc(state.host)} skills</label>` : ""}
    <div id="areas" class="flex flex-wrap gap-1 mb-3" aria-label="Filter by area"></div>
    <div id="results" class="space-y-2"><p class="text-slate-500">Loading…</p></div>`;
  api.transfers().then((t) => {
    const el = document.getElementById("offers");
    if (!el || !t.incoming?.length) return;
    el.innerHTML = t.incoming.map((o) => `
      <div class="rounded border border-sky-200 bg-sky-50 p-2 mb-2">
        <div><strong>${esc(o.from)}</strong> sent you <strong>${esc(o.label)}</strong> · ${o.free ? "free" : `${esc(o.price)} credits, held in escrow until delivery`}</div>
        ${o.skills.length > 1 ? `<div class="text-xs text-slate-600">${o.skills.map((x) => esc(x.title)).join(", ")}</div>` : ""}
        ${o.message ? `<div class="text-xs italic text-slate-600 mt-0.5">“${esc(o.message)}”</div>` : ""}
        <div class="flex gap-1 mt-1.5">
          <button data-action="accept-transfer" data-id="${o.id}" class="${btnPrimary}">${o.free ? "Accept" : `Pay ${esc(o.price)} & accept`}</button>
          <button data-action="decline-transfer" data-id="${o.id}" class="${btn}">Decline</button>
          ${o.free ? "" : `<span class="text-xs text-slate-500 self-center">You have ${esc(t.credits)}</span>`}
        </div>
      </div>`).join("");
  }).catch(() => {});
  api.areas().then((areas) => {
    const el = document.getElementById("areas");
    if (!el || !areas.length) return;
    const chip = (name, label, on) => `<button data-area="${esc(name)}" aria-pressed="${on}"
      class="px-2 py-0.5 rounded-full border text-xs ${on ? "bg-slate-900 text-white border-slate-900" : "bg-white text-slate-700"}">${esc(label)}</button>`;
    el.innerHTML = chip("", "All areas", !area) +
      areas.map((a) => chip(a.name, `${areaName(a.name)} · ${a.published}`, a.name === area)).join("");
  }).catch(() => {});
  try {
    const skills = await api.skills(q, area, state.host && state.hostOnly ? state.host : "", state.level);
    const results = document.getElementById("results");
    if (!results) return; // the person moved to another tab while this loaded
    results.innerHTML = skills.length ? skills.map((s) => `
      <button data-skill="${esc(s.name)}" class="block w-full text-left border rounded p-2 hover:bg-slate-50">
        <div class="font-medium">${esc(s.title)}</div>
        <div class="text-xs text-slate-500">${stageLabel(s.stage)} · ${esc(s.domain || "")}${s.domain ? " · " : ""}v${s.version}</div>
        ${s.field_label || s.apps?.length ? `<div class="text-xs text-slate-700 mt-0.5">${esc(s.field_label || "")}${s.field_label && s.apps?.length ? " · " : ""}${esc((s.apps || []).join(", "))}</div>` : ""}
        <div class="text-slate-600 mt-1">${esc(s.description.slice(0, 160))}${s.description.length > 160 ? "…" : ""}</div>
      </button>`).join("") : '<p class="text-slate-500">No skills match.</p>';
  } catch (e) { const r = document.getElementById("results"); if (r) r.innerHTML = `<p class="text-red-700">${esc(e.message)}</p>`; }
}

async function renderSkill(name) {
  panel().innerHTML = '<p class="text-slate-500">Loading…</p>';
  try {
    const s = await api.skill(name);
    state.openSkill = s;
    panel().innerHTML = `
      <button data-action="back-library" class="text-sky-700 mb-2">← Library</button>
      <h2 class="text-base font-semibold">${esc(s.title)}</h2>
      <div class="text-xs text-slate-500 mb-2">${stageLabel(s.stage)} · ${esc(s.name)} · v${s.version}${s.contributors.length ? ` · from ${esc(s.contributors.join(", "))}` : ""}</div>
      ${s.field_label || s.apps?.length ? `<div class="text-xs mb-2"><span class="text-slate-500">Field</span> ${esc(s.field_label || "—")} ${s.classified_by === "person" ? "✓" : "✨"} · <span class="text-slate-500">Apps</span> ${esc((s.apps || []).join(", ") || "—")}</div>` : ""}
      <div id="vote-box" class="flex items-center gap-2 mb-2">${voteHtml(s)}</div>
      ${s.usage ? `<div class="text-xs mb-2"><span class="text-slate-500">AI usage</span> ${Number(s.usage.avg_tokens).toLocaleString()} tokens/run${s.usage.avg_seconds ? ` · ${s.usage.avg_seconds} s` : ""} · ${s.usage.runs} runs${s.usage.intensity ? ` · <strong>${esc(s.usage.intensity)}</strong>` : ""}${s.usage.models?.[0] ? ` · mostly ${esc(s.usage.models[0].model)}` : ""}</div>` : ""}
      <p class="mb-2">${esc(s.description)}</p>
      ${s.traffic ? trafficHtml(s) : ""}
      <div class="flex flex-wrap gap-1 mb-3">
        ${s.worksheet ? `<button data-action="build-sheet" data-name="${esc(s.name)}" class="${btnPrimary}">▦ Build worksheet</button>` : ""}
        <button data-action="remember" class="${s.worksheet ? btn : btnPrimary}">Add to memory</button>
        ${state.host ? `<button data-action="insert-skill" class="${btn}">Insert steps here</button>` : ""}
        <button data-action="open-url" data-url="${esc(s.url)}" class="${btn}">Open in browser</button>
        ${s.can_send ? `<button data-action="send-skill" class="${btn}">⇢ Send to coworker</button>` : ""}
      </div>
      <div id="send-box"></div>
      <article class="border-t pt-2">${renderMarkdown(s.body)}</article>
      ${s.directions?.written ? `<details class="border-t mt-3 pt-2"><summary class="cursor-pointer font-medium">Directions for this road</summary>
        <article class="mt-1 text-xs">${renderMarkdown(s.directions.markdown)}</article></details>` : ""}
      ${s.junction ? `<details class="border-t mt-3 pt-2" ${s.junction.written ? "open" : ""}><summary class="cursor-pointer font-medium">At the end of this road: which way next</summary>
        <article class="mt-1 text-xs">${renderMarkdown(s.junction.markdown)}</article></details>` : ""}
      ${s.next_up?.length ? `<div class="border-t mt-3 pt-2"><div class="text-xs text-slate-500 mb-1">When you're done, people usually continue with</div>
        ${s.next_up.map((n) => `<button data-skill="${esc(n.name)}" class="block text-left text-sky-700 hover:underline">→ ${esc(n.title)}${n.traffic ? ` <span class="text-xs text-slate-500">(${n.traffic} trips)</span>` : ""}</button>`).join("")}</div>` : ""}`;
  } catch (e) { panel().innerHTML = `<p class="text-red-700">${esc(e.message)}</p>`; }
}

// ---------- building a skill's worksheet in Excel ----------
const BUILT_KEY = (name) => `skillcapture.built.${name}`;
const builtInputs = (name) => { try { return JSON.parse(settings.get(BUILT_KEY(name)) || "{}"); } catch { return {}; } };

async function renderBuild(name, from) {
  panel().innerHTML = '<p class="text-slate-500">Loading the worksheet…</p>';
  const b = from === "memory" ? memory.get(name) : await api.bundle(name);
  if (!b?.worksheet) { panel().innerHTML = '<p class="text-red-700">This skill has no worksheet.</p>'; return; }
  state.build = { bundle: b, from, inputs: { ...Object.fromEntries((b.worksheet.inputs || []).map((i) => [i.key, i.default ?? ""])), ...builtInputs(name) } };
  renderBuildPanel();
}

function sourcesFor(b) {
  // Source sheets are planned with the inputs they were last built with, so ranges line up.
  return Object.fromEntries(Object.entries(b.worksheet_sources || {}).map(([n, bp]) => [n, { ...bp, __inputs: builtInputs(n) }]));
}

function currentPlan() {
  const { bundle: b, inputs } = state.build;
  const sources = sourcesFor(b);
  const p = planSheet(b.worksheet, { inputs, commands: b.commands || {}, sources });
  return p;
}

function previewGrid(p) {
  if (!p.cells.length) return "";
  const at = (a) => { const m = /^([A-Z]+)(\d+)$/.exec(a); let c = 0; for (const ch of m[1]) c = c * 26 + ch.charCodeAt(0) - 64; return [Number(m[2]), c - 1]; };
  const grid = {};
  let maxR = 0, maxC = 0;
  for (const c of p.cells) { const [r, col] = at(c.address); grid[`${r}:${col}`] = c; maxR = Math.max(maxR, r); maxC = Math.max(maxC, col); }
  maxR = Math.min(maxR, 24); maxC = Math.min(maxC, 6);
  const rows = [];
  for (let r = 1; r <= maxR; r++) {
    rows.push(`<tr><td class="text-slate-400 pr-1 text-right">${r}</td>${Array.from({ length: maxC + 1 }, (_, c) => {
      const cell = grid[`${r}:${c}`];
      const txt = cell ? (cell.formula ?? cell.value) : "";
      return `<td class="border px-1 max-w-[9rem] truncate ${cell?.formula ? "font-mono text-[10px] text-sky-800" : ""} ${cell?.bold ? "font-semibold" : ""} ${cell?.input ? "bg-amber-50" : ""}" title="${esc(txt)}">${esc(txt)}</td>`;
    }).join("")}</tr>`);
  }
  return `<div class="overflow-x-auto border rounded mt-2"><table class="text-[11px] border-collapse"><thead><tr><th></th>${Array.from({ length: maxC + 1 }, (_, c) => `<th class="text-slate-400 font-normal">${colLetter(c)}</th>`).join("")}</tr></thead><tbody>${rows.join("")}</tbody></table></div>`;
}

function renderBuildPanel() {
  const { bundle: b, inputs } = state.build;
  const bp = b.worksheet;
  const p = currentPlan();
  const unverified = p.unverified.map((k) => b.commands?.[k]?.name || k);
  const excel = state.host === "Excel";
  panel().innerHTML = `
    <button data-action="${state.build.from === "memory" ? "back-memory" : "back-library"}" class="text-sky-700 mb-2">← ${state.build.from === "memory" ? "Memory" : "Library"}</button>
    <h2 class="text-base font-semibold">${esc(b.title)}</h2>
    <div class="text-xs text-slate-500 mb-2">${esc(areaName(b.provider || ""))} · ${esc(bp.kind || "table")} · ${bp.kind === "chart" ? `chart on “${esc(p.sheet || bp.source)}”` : `sheet “${esc(bp.sheet)}”`}</div>
    <form data-form="build" class="space-y-1.5">
      ${(bp.inputs || []).map((i) => `<label class="block text-xs">${esc(i.label || i.key)}
        ${i.type === "list" ? `<textarea name="${esc(i.key)}" rows="4" class="${input} font-mono text-xs">${esc(inputs[i.key])}</textarea>`
                            : `<input name="${esc(i.key)}" value="${esc(inputs[i.key])}" class="${input} text-xs">`}</label>`).join("")}
      ${(bp.inputs || []).length ? `<button class="${btn} text-xs">Update preview</button>` : ""}
    </form>
    ${p.warnings.length ? `<div class="mt-2 rounded border border-red-200 bg-red-50 text-red-800 text-xs p-2">${p.warnings.slice(0, 6).map(esc).join("<br>")}</div>` : ""}
    ${unverified.length ? `<div class="mt-2 rounded border border-amber-200 bg-amber-50 text-amber-900 text-xs p-2">◌ ${unverified.length} formula${unverified.length === 1 ? "" : "s"} not verified yet: ${esc(unverified.slice(0, 6).join(", "))}${unverified.length > 6 ? "…" : ""}. Check the results against ${esc(areaName(b.provider || ""))} before relying on them.</div>` : ""}
    ${bp.kind === "chart" ? `<div class="text-xs mt-2">${p.charts.map((c) => `${esc(c.type)} chart “${esc(c.title || "")}” at ${esc(c.at)}: ${c.series.map((s) => esc(s.nameText)).join(", ")}`).join("<br>")}</div>` : previewGrid(p)}
    <div class="flex gap-1 mt-3">
      <button data-action="apply-sheet" class="${btnPrimary} flex-1" ${excel && !p.warnings.some((w) => /Build “/.test(w)) ? "" : "disabled"}>${bp.kind === "chart" ? "Add the chart" : `Build “${esc(bp.sheet)}”`}</button>
    </div>
    <p class="text-xs text-slate-500 mt-1">${excel ? (bp.kind === "chart" ? "Adds the chart beside the source table." : "Creates the sheet, or rebuilds it if it already exists.") : "Open this in Excel to build it."}</p>`;
}

function renderMemory() {
  const items = memory.list();
  panel().innerHTML = items.length ? `
    <p class="text-xs text-slate-500 mb-2">Skills loaded on this device, ready for the AI working here. Sent from the map or added from the library.</p>
    <div class="space-y-2">${items.map((m) => `
      <div class="border rounded p-2">
        <div class="flex items-start gap-2">
          <button data-memory="${esc(m.name)}" class="flex-1 text-left font-medium text-sky-700 hover:underline">${esc(m.title)}</button>
          <button data-action="forget" data-name="${esc(m.name)}" class="text-xs text-slate-400 hover:text-red-700" aria-label="Remove ${esc(m.title)} from memory">remove</button>
        </div>
        <div class="text-xs text-slate-500">${stageLabel(m.stage)} · v${m.version}${m.from ? ` · from ${esc(m.from)}` : ""} · ${new Date(m.loaded_at).toLocaleString()}</div>
        ${m.fields?.length || m.apps?.length ? `<div class="text-xs text-slate-700">${esc((m.fields || []).join(" · "))}${m.apps?.length ? ` · ${esc(m.apps.join(", "))}` : ""}</div>` : ""}
        ${m.resources?.length ? `<div class="text-xs text-slate-600 mt-1">📎 ${m.resources.length} resource${m.resources.length > 1 ? "s" : ""}</div>` : ""}
      </div>`).join("")}</div>
    <button data-action="forget-all" class="${btn} mt-3 text-xs">Clear memory</button>`
    : `<p class="text-slate-500">Nothing in memory yet. Click a road on the Skill map and choose <strong>Send to my add-in</strong>, or open a skill here and choose <strong>Add to memory</strong>.</p>`;
}

function renderMemoryItem(name) {
  const m = memory.get(name);
  if (!m) return renderMemory();
  state.openSkill = { title: m.title, body: String(m.skill_md || "").replace(/^---[\s\S]*?---\s*/, ""), name: m.name };
  panel().innerHTML = `
    <button data-action="back-memory" class="text-sky-700 mb-2">← Memory</button>
    <h2 class="text-base font-semibold">${esc(m.title)}</h2>
    <div class="text-xs text-slate-500 mb-2">In memory since ${new Date(m.loaded_at).toLocaleString()}${m.from ? ` · sent by ${esc(m.from)}` : ""}</div>
    <div class="flex gap-1 mb-2">
      ${m.worksheet ? `<button data-action="build-sheet" data-name="${esc(m.name)}" data-from="memory" class="${btnPrimary}">▦ Build worksheet</button>` : ""}
      ${state.host ? `<button data-action="insert-skill" class="${btn}">Insert steps here</button>` : ""}
      <button data-action="copy-context" data-name="${esc(m.name)}" class="${btn}">Copy for AI</button>
    </div>
    ${m.resources?.length ? `<div class="mb-2"><div class="text-xs text-slate-500 mb-1">Resources</div>${m.resources.map((r) => `<div class="text-xs">📎 <button data-action="open-url" data-url="${esc(r.url)}" class="text-sky-700 hover:underline">${esc(r.name)}</button> <span class="text-slate-400">${esc(r.key)}</span></div>`).join("")}</div>` : ""}
    <article class="border-t pt-2">${renderMarkdown(state.openSkill.body)}</article>
    ${(m.directions || []).map((d) => `<details class="border-t mt-2 pt-2"><summary class="cursor-pointer font-medium">${esc(d.title)}</summary><article class="text-xs mt-1">${renderMarkdown(d.markdown)}</article></details>`).join("")}`;
}

function renderRecord() {
  const s = state.capture.state();
  if (!s.recording && state.recovered) {
    const r = state.recovered;
    panel().innerHTML = `
      <div class="space-y-2 rounded border border-sky-200 bg-sky-50 p-2">
        <p><strong>Recovered ${r.steps.length} unsaved step${r.steps.length === 1 ? "" : "s"}</strong> from a recording that didn't finish${r.savedAt ? ` (${new Date(r.savedAt).toLocaleString()})` : ""}.</p>
        <ol class="list-decimal ml-5 text-slate-600">${r.steps.map((st) => `<li>${esc(st.label)}</li>`).join("")}</ol>
        <div class="flex gap-1"><button data-action="resume-recording" class="${btnPrimary} flex-1">Resume</button><button data-action="discard-recovered" class="${btn}">Discard</button></div>
      </div>`;
    return;
  }
  if (!s.recording && state.sheetCapture) { panel().innerHTML = sheetCaptureHtml(state.sheetCapture); return; }
  if (!s.recording) {
    const excel = state.host === "Excel";
    panel().innerHTML = `
      <div class="space-y-2 rounded border p-2 mb-3">
        <p><strong>▦ Capture this sheet</strong>: Skill Capture reads the active worksheet, works out what it's attempting, documents every formula (BQL, FactSet or Excel) and writes a draft skill for review.</p>
        <p class="text-xs text-slate-500">Only labels and formulas are sent, never the numbers.</p>
        <button data-action="capture-sheet" class="${btnPrimary} w-full" ${excel ? "" : "disabled"}>Capture this sheet</button>
        ${excel ? "" : '<p class="text-xs text-slate-500">Works in Excel.</p>'}
      </div>
      <div class="space-y-2">
        <p>Show Skill Capture how you do a task. Start recording, do it once as you normally would, and add notes for steps Office can't see (checks, decisions, where data comes from).</p>
        <p class="text-xs text-slate-500">Only step types are recorded (like "Sort data"), never file names, cell values or text.</p>
        <button data-action="start-recording" class="${btnPrimary} w-full" ${state.host ? "" : "disabled"}>Start recording</button>
      </div>`;
    return;
  }
  panel().innerHTML = `
    <div class="space-y-2">
      <form data-form="note" class="flex gap-1">
        <input name="note" placeholder="Add a step in your words" class="${input}" aria-label="Add a step">
        <button class="${btn}">Add</button>
      </form>
      <ol id="rec-steps" class="list-decimal ml-5 space-y-1"></ol>
      <div class="flex gap-1">
        <button data-action="finish-recording" class="${btnPrimary} flex-1">Finish</button>
        <button data-action="discard-recording" class="${btn}">Discard</button>
      </div>
    </div>`;
  renderRecordSteps();
}

// Observe → Interpret → Document → Write for the active worksheet.
async function captureActiveSheet() {
  if (state.host !== "Excel" || !window.Excel) { flash("Capturing a sheet works in Excel.", "error"); return render(); }
  state.sheetCapture = { busy: true };
  if (state.tab === "record") renderRecord();
  try {
    const { sheet, address, formulas, values } = await window.Excel.run(async (ctx) => {
      const ws = ctx.workbook.worksheets.getActiveWorksheet();
      const used = ws.getUsedRange(true);
      ws.load("name");
      used.load(["address", "formulas", "values"]);
      await ctx.sync();
      return { sheet: ws.name, address: used.address, formulas: used.formulas, values: used.values };
    });
    const { cells, truncated } = observeCells(formulas, values, address);
    const result = await api.captureSheet({ sheet, address: String(address).split("!").pop(), cells });
    state.sheetCapture = { result, truncated };
  } catch (e) {
    state.sheetCapture = { error: e.message || String(e) };
  }
  if (state.tab === "record") renderRecord();
}

function sheetCaptureHtml(c) {
  const close = `<button data-action="close-sheet-capture" class="${btn}">Done</button>`;
  if (c.busy) return '<p class="text-slate-500">Reading the sheet: observing, interpreting, documenting, writing…</p>';
  if (c.error) return `<div class="rounded border border-red-200 bg-red-50 text-red-800 p-2 mb-2">${esc(c.error)}</div>${close}`;
  const r = c.result;
  const stage = (n, label, text) => `<li class="border rounded p-2"><div class="font-medium">${n}. ${label}</div><div class="text-xs text-slate-600">${text}</div></li>`;
  return `
    <h2 class="text-base font-semibold">${esc(r.interpreted.title || r.sheet)}</h2>
    <div class="text-xs text-slate-500 mb-2">${esc(r.provider_name)} · “${esc(r.sheet)}” · interpreted by ${r.interpreted_by === "ai" ? "AI" : "rules"}</div>
    <ol class="space-y-1 mb-2">
      ${stage(1, "Observed", esc(r.observed) + (c.truncated ? " (sheet truncated)" : ""))}
      ${stage(2, "Interpreted", esc(r.interpreted.purpose || ""))}
      ${stage(3, "Documented", `${r.documented.formulas} formula pattern${r.documented.formulas === 1 ? "" : "s"}, ${r.documented.commands} from the library${r.documented.new_commands ? `, ${r.documented.new_commands} new (unverified)` : ""}<br>${r.documented.files.map(esc).join(" · ")}`)}
      ${stage(4, "Written", r.written ? `Draft skill <span class="font-mono">${esc(r.written.name)}</span>, sent to reviewers` : "Not written")}
    </ol>
    ${(r.interpreted.risks || []).length ? `<div class="rounded border border-amber-200 bg-amber-50 text-amber-900 text-xs p-2 mb-2">${r.interpreted.risks.slice(0, 5).map(esc).join("<br>")}</div>` : ""}
    <div class="flex gap-1">
      <button data-action="open-url" data-url="${esc(r.url)}" class="${btnPrimary} flex-1">Open the files</button>
      ${close}
    </div>`;
}

// Send the open skill straight to a coworker, free or (for skills you authored or review) for credits.
async function renderSendBox() {
  const box = document.getElementById("send-box");
  const s = state.openSkill;
  box.innerHTML = '<p class="text-slate-500">Loading coworkers…</p>';
  const people = await api.coworkers();
  box.innerHTML = `
    <form data-form="send" class="rounded border p-2 mb-2 space-y-1.5">
      <div class="font-medium">Send “${esc(s.title)}” to a coworker</div>
      <p class="text-xs text-slate-500">Straight to one person. It stays at its level.</p>
      <select name="recipient_id" required class="${input}" aria-label="Coworker"><option value="">Choose a coworker…</option>
        ${people.map((p) => `<option value="${p.id}">${esc(p.name)}${p.department ? ` · ${esc(p.department)}` : ""}</option>`).join("")}</select>
      ${s.can_sell ? `<input name="price" type="number" min="0" step="0.01" placeholder="Price in credits (blank = free)" class="${input}" aria-label="Price in credits">` : '<p class="text-xs text-slate-500">Free (you can charge only for skills you authored or review).</p>'}
      <textarea name="message" rows="2" maxlength="1000" placeholder="Message (optional)" class="${input}"></textarea>
      <label class="flex items-center gap-1.5 text-xs"><input type="checkbox" name="allow_forward" value="1"> Let them pass it on (free)</label>
      <div class="flex gap-1"><button class="${btnPrimary} flex-1">Send</button><button type="button" data-action="cancel-send" class="${btn}">Cancel</button></div>
    </form>`;
}

function renderRecordSteps() {
  const ol = document.getElementById("rec-steps");
  const rec = state.capture.state().recording;
  if (!ol || !rec) return;
  ol.innerHTML = rec.steps.length ? rec.steps.map((st, i) => `
    <li><span>${esc(st.label)}</span> <button data-action="remove-step" data-index="${i}" class="text-xs text-slate-400 hover:text-red-700" aria-label="Remove step">remove</button></li>`).join("")
    : '<li class="list-none -ml-5 text-slate-500">Do the task in your document. Steps appear here.</li>';
}

function renderFinish(steps) {
  state.pendingSteps = steps;
  panel().innerHTML = `
    <form data-form="procedure" class="space-y-2">
      <h2 class="font-semibold">Submit for review</h2>
      <label class="block">Title<input name="title" required class="${input}" placeholder="e.g. Reconcile the bank statement"></label>
      <label class="block">Area<input name="domain" class="${input}" value="${esc(state.me.domains?.[0] || "")}" placeholder="e.g. finance"></label>
      <label class="block">When should someone use this?<textarea name="description" rows="2" class="${input}"></textarea></label>
      <div><div class="text-slate-500 mb-1">${steps.length} steps</div>
        <ol class="list-decimal ml-5 text-slate-600">${steps.map((s) => `<li>${esc(s.label)}</li>`).join("")}</ol></div>
      <div class="flex gap-1"><button class="${btnPrimary} flex-1">Submit</button><button type="button" data-action="discard-finish" class="${btn}">Cancel</button></div>
    </form>`;
}

async function renderReview() {
  panel().innerHTML = '<p class="text-slate-500">Loading…</p>';
  try {
    const items = await api.candidates();
    panel().innerHTML = items.length ? `<div class="space-y-2">${items.map((c) => `
      <button data-candidate="${c.id}" class="block w-full text-left border rounded p-2 hover:bg-slate-50">
        <div class="font-medium">${esc(c.title)}</div>
        <div class="text-xs text-slate-500">${esc(c.domain || "no area")} · ${c.origin === "manual" ? "recorded" : `seen ${c.occurrences}× by ${c.people}`} · ${c.drafted ? "draft ready" : "drafting…"}</div>
      </button>`).join("")}</div>` : '<p class="text-slate-500">Nothing waiting for you.</p>';
  } catch (e) { panel().innerHTML = `<p class="text-red-700">${esc(e.message)}</p>`; }
}

async function renderCandidate(id) {
  panel().innerHTML = '<p class="text-slate-500">Loading…</p>';
  try {
    const c = await api.candidate(id);
    panel().innerHTML = `
      <button data-action="back-review" class="text-sky-700 mb-2">← Review</button>
      <h2 class="text-base font-semibold">${esc(c.title)}</h2>
      <div class="text-xs text-slate-500 mb-2">${esc(c.domain || "no area")} · by ${esc(c.contributors.join(", ") || "—")}</div>
      <ol class="list-decimal ml-5 mb-2">${c.steps.map((s) => `<li>${esc(s.label)}</li>`).join("")}</ol>
      ${c.draft_body ? `<p class="mb-1">${esc(c.draft_description || "")}</p><article class="border rounded p-2 bg-slate-50 mb-2">${renderMarkdown(c.draft_body)}</article>`
                     : '<p class="text-slate-500 mb-2">Draft is being written…</p>'}
      <div class="flex flex-wrap gap-1">
        ${c.can_approve && c.draft_body ? `<button data-action="approve" data-id="${c.id}" class="${btnPrimary}">Approve &amp; publish</button>` : ""}
        <button data-action="open-url" data-url="${esc(c.url)}" class="${btn}">Edit in console</button>
        ${c.can_approve ? `<button data-action="reject" data-id="${c.id}" class="${btn} text-red-700">Reject</button>` : ""}
      </div>`;
  } catch (e) { panel().innerHTML = `<p class="text-red-700">${esc(e.message)}</p>`; }
}

function renderSettings() {
  const on = state.capture.state().capturing;
  const events = Object.entries(state.wired?.events || {});
  panel().innerHTML = `
    <div class="space-y-3">
      <div>Signed in as <strong>${esc(state.me.name)}</strong> (${esc(state.me.role)})</div>
      <label class="flex items-start gap-2">
        <input type="checkbox" data-action="toggle-capture" ${on ? "checked" : ""} ${state.me.capture_enabled && state.host ? "" : "disabled"} class="mt-1">
        <span><strong>Capture my workflow</strong><br><span class="text-slate-500">Share the types of steps you take here (like "Insert rows", "Add a slide") so repeated workflows can become skills. Never file names, values or text. Co-authors' changes are ignored.</span></span>
      </label>
      ${state.me.capture_enabled ? "" : '<p class="text-amber-800">Capture is turned off by your administrator.</p>'}
      ${events.length ? `<details><summary class="cursor-pointer text-slate-600">What this ${esc(state.host)} version can see</summary>
        <ul class="text-xs mt-1">${events.map(([k, v]) => `<li>${v ? "✓" : "–"} ${esc(k)}</li>`).join("")}</ul></details>` : ""}
      <div class="flex gap-1">
        <button data-action="open-url" data-url="${esc(state.me.console_url)}" class="${btn}">Open web console</button>
        <button data-action="disconnect" class="${btn}">Disconnect</button>
      </div>
    </div>`;
}

// ---------- actions ----------
document.addEventListener("click", async (ev) => {
  if (state.tab === "flows" && flowPane().onClick(ev)) return;
  const t = ev.target.closest("[data-tab],[data-action],[data-skill],[data-candidate],[data-area],[data-memory]");
  if (!t) return;
  if (t.dataset.memory) return renderMemoryItem(t.dataset.memory);
  if (t.dataset.area !== undefined && !t.dataset.action) return renderLibrary(state.query, t.dataset.area);
  if (t.dataset.tab) { state.tab = t.dataset.tab; return render(); }
  if (t.dataset.skill) return renderSkill(t.dataset.skill);
  if (t.dataset.candidate) return renderCandidate(t.dataset.candidate);

  const a = t.dataset.action;
  try {
    if (a?.startsWith("flow-")) { await flowPane().onAction(a, t); return; }
    if (a === "connect") {
      const url = `${root.dataset.connectUrl}?host=${encodeURIComponent(state.host || "")}&platform=${encodeURIComponent(window.Office?.context?.diagnostics?.platform || "")}`;
      if (!state.host) { window.open(url, "_blank", "noopener"); return; }
      const { token } = await connectDialog(url);
      api.setToken(token);
      await loadMe();
      flash(`Connected as ${state.me.name}.`);
      render();
    } else if (a === "back-library") { renderLibrary(); }
    else if (a === "back-review") { renderReview(); }
    else if (a === "open-url") { openInBrowser(t.dataset.url); }
    else if (a === "remember") {
      memory.add(await api.bundle(state.openSkill.name));
      flash(`“${state.openSkill.title}” added to memory.`); state.tab = "memory"; render();
    }
    else if (a === "forget") { memory.remove(t.dataset.name); render(); }
    else if (a === "forget-all") { memory.clear(); render(); }
    else if (a === "back-memory") { renderMemory(); }
    else if (a === "copy-context") {
      await navigator.clipboard?.writeText(memory.asContext(t.dataset.name)).catch(() => {});
      flash("Copied the skill, its directions and resources for your AI."); render(); renderMemoryItem(t.dataset.name);
    }
    else if (a === "vote") {
      const r = await api.vote(state.openSkill.name, Number(t.dataset.value));
      Object.assign(state.openSkill, { votes: r.votes, my_vote: r.my_vote });
      document.getElementById("vote-box").innerHTML = voteHtml(state.openSkill);
    }
    else if (a === "insert-skill") { await insertText(toPlainSteps(state.openSkill)); flash("Steps inserted."); render(); }
    else if (a === "prompt") {
      const choice = t.dataset.choice;
      const title = document.getElementById("prompt-title")?.value || "";
      const r = await api.respondPrompt(t.dataset.id, choice, title);
      state.prompts = state.prompts.filter((p) => String(p.id) !== t.dataset.id);
      flash(r.candidate ? `Sent “${r.candidate.title}” to the reviewers. Nothing changes until it's approved, and a rest stop keeps the current version.`
        : choice === "snooze" ? "OK, I'll ask again in a few days." : "Got it. I won't ask about this again.");
      render();
    }
    else if (a === "resume-recording") { state.capture.restoreRecording(state.recovered.steps); state.recovered = null; renderRecord(); updateCaptureBadge(); }
    else if (a === "discard-recovered") { state.recovered = null; settings.set(DRAFT_KEY, null); renderRecord(); }
    else if (a === "send-skill") { await renderSendBox(); }
    else if (a === "cancel-send") { document.getElementById("send-box").innerHTML = ""; }
    else if (a === "accept-transfer" || a === "decline-transfer") {
      const r = await (a === "accept-transfer" ? api.acceptTransfer(t.dataset.id) : api.declineTransfer(t.dataset.id));
      flash(r.status === "settled" ? `Contract settled: ${r.label} is in your library (Sent to me).` : "Declined.");
      if (r.status === "settled") { state.level = "received"; settings.set("skillcapture.level", "received"); }
      render();
    }
    else if (a === "set-level") { state.level = t.dataset.level; settings.set("skillcapture.level", state.level || null); renderLibrary(); }
    else if (a === "capture-sheet") { await captureActiveSheet(); }
    else if (a === "close-sheet-capture") { state.sheetCapture = null; renderRecord(); }
    else if (a === "build-sheet") { await renderBuild(t.dataset.name, t.dataset.from); }
    else if (a === "apply-sheet") {
      const p = currentPlan();
      const out = await applySheet(p, window.Excel);
      settings.set(BUILT_KEY(state.build.bundle.name), JSON.stringify(state.build.inputs));
      flash(p.kind === "chart" ? `Added the chart to “${out.sheet}”.` : `Built “${out.sheet}”: ${out.cells} cells. Formulas calculate in your ${areaName(state.build.bundle.provider || "")} session.`);
      render(); renderBuildPanel();
    }
    else if (a === "start-recording") { state.capture.startRecording(); renderRecord(); updateCaptureBadge(); }
    else if (a === "discard-recording") { state.capture.stopRecording(); settings.set(DRAFT_KEY, null); renderRecord(); }
    else if (a === "remove-step") { state.capture.removeStep(Number(t.dataset.index)); }
    else if (a === "finish-recording") {
      const steps = state.capture.stopRecording();
      if (!steps.length) { flash("No steps were recorded.", "error"); return render(); }
      renderFinish(steps);
    }
    else if (a === "discard-finish") { state.pendingSteps = null; settings.set(DRAFT_KEY, null); renderRecord(); }
    else if (a === "approve") {
      const r = await api.approve(t.dataset.id);
      state.me.open_reviews = Math.max(0, (state.me.open_reviews || 1) - 1);
      flash(`Published ${r.name} v${r.version}.`); render();
    }
    else if (a === "reject") {
      const notes = prompt("Why isn't this a skill? (optional)") ?? null;
      if (notes === null) return;
      await api.reject(t.dataset.id, notes);
      state.me.open_reviews = Math.max(0, (state.me.open_reviews || 1) - 1);
      flash("Rejected."); render();
    }
    else if (a === "disconnect") { await api.disconnect(); state.capture.setCapturing(false); state.me = null; render(); }
  } catch (e) { flash(e.message, "error"); render(); }
});

document.addEventListener("change", async (ev) => {
  if (ev.target.dataset.action === "host-only") { state.hostOnly = ev.target.checked; settings.set("skillcapture.hostOnly", state.hostOnly ? "1" : "0"); return renderLibrary(); }
  if (ev.target.dataset.action !== "toggle-capture") return;
  const on = ev.target.checked;
  settings.set(CAPTURE_KEY, on ? "on" : "off");
  state.capture.setCapturing(on);
  try { await setAutoLoad(on); } catch { /* not supported on this client */ }
  updateCaptureBadge();
});

document.addEventListener("submit", async (ev) => {
  ev.preventDefault();
  const f = ev.target;
  const data = Object.fromEntries(new FormData(f));
  try {
    if (f.dataset.form === "search") return renderLibrary(data.q, state.area);
    if (f.dataset.form?.startsWith("flow-")) { await flowPane().onSubmit(f, data); return; }
    if (f.dataset.form === "send") {
      const r = await api.sendSkills({ skills: [state.openSkill.name], recipient_id: data.recipient_id, price: data.price || 0, message: data.message, allow_forward: data.allow_forward === "1" });
      document.getElementById("send-box").innerHTML = `<p class="rounded border border-emerald-200 bg-emerald-50 p-2 mb-2">Sent to ${esc(r.to)}${r.free ? "" : ` for ${esc(r.price)} credits`}. They'll see it next time they open their library.</p>`;
      return;
    }
    if (f.dataset.form === "build") { Object.assign(state.build.inputs, data); return renderBuildPanel(); }
    if (f.dataset.form === "note") {
      if (data.note.trim()) state.capture.addNote(manualStep(state.host, data.note));
      f.reset(); f.note.focus();
    }
    if (f.dataset.form === "procedure") {
      await api.submitProcedure({ host: state.host, title: data.title, domain: data.domain, description: data.description, steps: state.pendingSteps });
      state.pendingSteps = null;
      settings.set(DRAFT_KEY, null);
      flash("Submitted. A reviewer for that area has been notified.");
      state.tab = "record"; render();
    }
  } catch (e) { flash(e.message, "error"); render(); }
});

window.addEventListener("pagehide", () => state.capture?.flush().catch(() => {}));

boot();

// ---------- flows (drag-and-drop flowchart) ----------
function flowPane() {
  flows ||= createFlowPane({ api, panel, esc, btn, btnPrimary, input, flash, rerender: () => render(), host: () => state.host });
  return flows;
}
document.addEventListener("dragstart", (ev) => { if (state.tab === "flows") flowPane().onDragStart(ev); });
document.addEventListener("dragover", (ev) => { if (state.tab === "flows") flowPane().onDragOver(ev); });
document.addEventListener("drop", (ev) => { if (state.tab === "flows") flowPane().onDrop(ev); });
document.addEventListener("pointerdown", (ev) => { if (state.tab === "flows") flowPane().onPointerDown(ev); });
document.addEventListener("pointermove", (ev) => { if (state.tab === "flows") flowPane().onPointerMove(ev); }, { passive: false });
document.addEventListener("pointerup", (ev) => { if (state.tab === "flows") flowPane().onPointerUp(ev); });
document.addEventListener("pointercancel", (ev) => { if (state.tab === "flows") flowPane().onPointerUp(ev); });
document.addEventListener("input", (ev) => { if (state.tab === "flows") flowPane().onInput(ev); });
document.addEventListener("change", (ev) => { if (state.tab === "flows") flowPane().onInput(ev); });
