import { createApi, settings } from "addin/api";
import { createCapture } from "addin/capture";
import { manualStep } from "addin/vocabulary";
import { wireHost, setAutoLoad, insertText, openInBrowser, connectDialog } from "addin/office_hosts";
import { renderMarkdown, toPlainSteps } from "addin/markdown";

const root = document.getElementById("app");
const view = document.getElementById("view");
const api = createApi();
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const CAPTURE_KEY = "skillcapture.capturing";
const areaName = (n) => n.length <= 3 ? n.toUpperCase() : n.split(/[-_\s]+/).map((w) => w[0].toUpperCase() + w.slice(1)).join(" ");

const state = { host: null, me: null, tab: "library", capture: null, wired: null, flash: null, flashKind: "ok" };
let flushTimer = null;

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
  state.capture.onChange(() => { if (state.tab === "record") renderRecordSteps(); updateCaptureBadge(); });

  if (state.host && ["Excel", "Word", "PowerPoint"].includes(state.host)) {
    try { state.wired = await wireHost(state.host, (k) => state.capture.record(k)); }
    catch (e) { state.wired = { supported: false, error: e.message, events: {} }; }
  }
  await loadMe();
  render();
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
  } catch (e) {
    state.me = null;
    if (e.status !== 401) flash(e.message, "error");
  }
}

// ---------- rendering ----------
function render() {
  if (!state.me) return renderConnect();
  const tabs = [["library", "Library"], ["record", "Record"]];
  if (state.me.reviewer) tabs.push(["review", `Review${state.me.open_reviews ? ` (${state.me.open_reviews})` : ""}`]);
  tabs.push(["settings", "Settings"]);
  view.innerHTML = `
    <div class="flex justify-end -mt-1 mb-1"><span id="capture-badge" class="text-xs"></span></div>
    <nav class="flex mb-3 border-b" role="tablist">
      ${tabs.map(([id, label]) => `<button role="tab" data-tab="${id}" aria-selected="${state.tab === id}"
         class="px-2 py-1.5 -mb-px border-b-2 whitespace-nowrap ${state.tab === id ? "border-slate-900 font-semibold" : "border-transparent text-slate-500"}">${esc(label)}</button>`).join("")}
    </nav>
    ${flashHtml()}
    <section id="panel"></section>`;
  updateCaptureBadge();
  ({ library: renderLibrary, record: renderRecord, review: renderReview, settings: renderSettings }[state.tab])();
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
  panel().innerHTML = `
    <form data-form="search" class="flex gap-1 mb-2">
      <input name="q" value="${esc(q)}" placeholder="Search skills" class="${input}" aria-label="Search skills">
      <button class="${btn}">Search</button>
    </form>
    <div id="areas" class="flex flex-wrap gap-1 mb-3" aria-label="Filter by area"></div>
    <div id="results" class="space-y-2"><p class="text-slate-500">Loading…</p></div>`;
  api.areas().then((areas) => {
    const el = document.getElementById("areas");
    if (!el || !areas.length) return;
    const chip = (name, label, on) => `<button data-area="${esc(name)}" aria-pressed="${on}"
      class="px-2 py-0.5 rounded-full border text-xs ${on ? "bg-slate-900 text-white border-slate-900" : "bg-white text-slate-700"}">${esc(label)}</button>`;
    el.innerHTML = chip("", "All areas", !area) +
      areas.map((a) => chip(a.name, `${areaName(a.name)} · ${a.published}`, a.name === area)).join("");
  }).catch(() => {});
  try {
    const skills = await api.skills(q, area);
    document.getElementById("results").innerHTML = skills.length ? skills.map((s) => `
      <button data-skill="${esc(s.name)}" class="block w-full text-left border rounded p-2 hover:bg-slate-50">
        <div class="font-medium">${esc(s.title)}</div>
        <div class="text-xs text-slate-500">${stageLabel(s.stage)} · ${esc(s.domain || "")}${s.domain ? " · " : ""}v${s.version}</div>
        <div class="text-slate-600 mt-1">${esc(s.description.slice(0, 160))}${s.description.length > 160 ? "…" : ""}</div>
      </button>`).join("") : '<p class="text-slate-500">No skills match.</p>';
  } catch (e) { document.getElementById("results").innerHTML = `<p class="text-red-700">${esc(e.message)}</p>`; }
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
      <div id="vote-box" class="flex items-center gap-2 mb-2">${voteHtml(s)}</div>
      <p class="mb-2">${esc(s.description)}</p>
      ${s.traffic ? trafficHtml(s) : ""}
      <div class="flex gap-1 mb-3">
        ${state.host ? `<button data-action="insert-skill" class="${btn}">Insert steps here</button>` : ""}
        <button data-action="open-url" data-url="${esc(s.url)}" class="${btn}">Open in browser</button>
      </div>
      <article class="border-t pt-2">${renderMarkdown(s.body)}</article>
      ${s.directions?.written ? `<details class="border-t mt-3 pt-2"><summary class="cursor-pointer font-medium">Directions for this road</summary>
        <article class="mt-1 text-xs">${renderMarkdown(s.directions.markdown)}</article></details>` : ""}
      ${s.junction ? `<details class="border-t mt-3 pt-2" ${s.junction.written ? "open" : ""}><summary class="cursor-pointer font-medium">At the end of this road: which way next</summary>
        <article class="mt-1 text-xs">${renderMarkdown(s.junction.markdown)}</article></details>` : ""}
      ${s.next_up?.length ? `<div class="border-t mt-3 pt-2"><div class="text-xs text-slate-500 mb-1">When you're done, people usually continue with</div>
        ${s.next_up.map((n) => `<button data-skill="${esc(n.name)}" class="block text-left text-sky-700 hover:underline">→ ${esc(n.title)}${n.traffic ? ` <span class="text-xs text-slate-500">(${n.traffic} trips)</span>` : ""}</button>`).join("")}</div>` : ""}`;
  } catch (e) { panel().innerHTML = `<p class="text-red-700">${esc(e.message)}</p>`; }
}

function renderRecord() {
  const s = state.capture.state();
  if (!s.recording) {
    panel().innerHTML = `
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
  const t = ev.target.closest("[data-tab],[data-action],[data-skill],[data-candidate],[data-area]");
  if (!t) return;
  if (t.dataset.area !== undefined && !t.dataset.action) return renderLibrary(state.query, t.dataset.area);
  if (t.dataset.tab) { state.tab = t.dataset.tab; return render(); }
  if (t.dataset.skill) return renderSkill(t.dataset.skill);
  if (t.dataset.candidate) return renderCandidate(t.dataset.candidate);

  const a = t.dataset.action;
  try {
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
    else if (a === "vote") {
      const r = await api.vote(state.openSkill.name, Number(t.dataset.value));
      Object.assign(state.openSkill, { votes: r.votes, my_vote: r.my_vote });
      document.getElementById("vote-box").innerHTML = voteHtml(state.openSkill);
    }
    else if (a === "insert-skill") { await insertText(toPlainSteps(state.openSkill)); flash("Steps inserted."); render(); }
    else if (a === "start-recording") { state.capture.startRecording(); renderRecord(); updateCaptureBadge(); }
    else if (a === "discard-recording") { state.capture.stopRecording(); renderRecord(); }
    else if (a === "remove-step") { state.capture.removeStep(Number(t.dataset.index)); }
    else if (a === "finish-recording") {
      const steps = state.capture.stopRecording();
      if (!steps.length) { flash("No steps were recorded.", "error"); return render(); }
      renderFinish(steps);
    }
    else if (a === "discard-finish") { state.pendingSteps = null; renderRecord(); }
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
    if (f.dataset.form === "note") {
      if (data.note.trim()) state.capture.addNote(manualStep(state.host, data.note));
      f.reset(); f.note.focus();
    }
    if (f.dataset.form === "procedure") {
      await api.submitProcedure({ host: state.host, title: data.title, domain: data.domain, description: data.description, steps: state.pendingSteps });
      state.pendingSteps = null;
      flash("Submitted. A reviewer for that area has been notified.");
      state.tab = "record"; render();
    }
  } catch (e) { flash(e.message, "error"); render(); }
});

window.addEventListener("pagehide", () => state.capture?.flush().catch(() => {}));

boot();
