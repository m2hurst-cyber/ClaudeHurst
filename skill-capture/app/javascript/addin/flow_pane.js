// The add-in's Flows tab: a vertical flowchart you build by drag and drop (skills or blank tasks from the
// palette, tasks dragged to reorder), then run: each task happens in order and hands off to the next,
// in the app or agent that does it.
import { LANES, stepFrom, insertAt, move, remove, update, problems, isPause, pauseLabel } from "addin/flow_model";

const HOLD_MS = 350; // press and hold this long to pick a task up on a touch screen

export function createFlowPane({ api, panel, esc, btn, btnPrimary, input, flash, rerender, host }) {
  const st = { view: "list", data: null, edit: null, run: null, who: null, open: null, palette: [] };

  const whoLabel = (a) => (st.who || []).find((w) => w.value === a)?.label || (a === "me" ? "Me" : a);
  const appBadge = (app) => `<span class="text-[10px] px-1 rounded border ${app === host() ? "bg-sky-50 border-sky-300" : "bg-white"}">${esc(app)}</span>`;

  async function loadWho() {
    if (st.who) return;
    const r = await api.flowAgents().catch(() => ({ agents: [], people: [] }));
    st.who = [{ value: "me", label: "Me" }, ...r.agents.map((a) => ({ value: a.assignee, label: `🤖 ${a.name}` })), ...r.people.map((p) => ({ value: p.assignee, label: p.name }))];
  }

  async function render() {
    if (st.view === "edit") return renderEdit();
    if (st.view === "run") return renderRun();
    panel().innerHTML = '<p class="text-slate-500">Loading flows…</p>';
    try { st.data = await api.flows(); } catch (e) { panel().innerHTML = `<p class="text-red-700">${esc(e.message)}</p>`; return; }
    const d = st.data;
    const waiting = d.runs.filter((r) => r.current?.mine);
    panel().innerHTML = `
      ${waiting.map((r) => `<div class="rounded border border-amber-300 bg-amber-50 p-2 mb-2"><div class="font-medium">Your turn: ${esc(r.current.title)}</div>
        <div class="text-xs text-slate-600">Task ${r.current_index + 1} of ${r.total} in “${esc(r.flow)}” · ${esc(r.current.app)}</div>
        <button data-action="flow-open-run" data-id="${r.id}" class="${btnPrimary} mt-1">Open</button></div>`).join("")}
      <p class="text-xs text-slate-500 mb-2">Sequence tasks across apps, people and agents. Run a flow and each task hands off to the next when it's done.</p>
      <div class="flex flex-wrap gap-1 mb-3">
        <button data-action="flow-new" class="${btn}">＋ Blank flow</button>
        ${d.templates.map((t) => `<button data-action="flow-template" data-key="${esc(t.key)}" class="${btnPrimary}" title="${esc(t.description)}">${esc(t.name)}</button>`).join("")}
      </div>
      <div class="space-y-1.5">
        ${d.flows.length ? d.flows.map((f) => `<div class="border rounded p-2"><div class="font-medium">${esc(f.name)}</div>
          <div class="text-xs text-slate-500">${f.steps.length} tasks · ${esc([...new Set(f.steps.map((s) => s.app))].join(" → "))}</div>
          <div class="flex gap-1 mt-1"><button data-action="flow-edit" data-id="${f.id}" class="${btn} text-xs">Edit</button><button data-action="flow-run" data-id="${f.id}" class="${btn} text-xs">▶ Run</button></div></div>`).join("")
          : '<p class="text-slate-500">No flows yet.</p>'}
      </div>
      ${d.runs.filter((r) => !r.current?.mine).length ? `<div class="mt-3 text-xs text-slate-500">Running: ${d.runs.filter((r) => !r.current?.mine).map((r) => `<button data-action="flow-open-run" data-id="${r.id}" class="text-sky-700 hover:underline">${esc(r.flow)} (task ${r.current_index + 1}/${r.total})</button>`).join(", ")}</div>` : ""}`;
  }

  // ---------- the flowchart editor ----------
  function renderEdit() {
    const e = st.edit;
    const zone = (i) => `<div data-drop="${i}" class="flow-drop h-3 my-0.5 rounded transition-all" aria-hidden="true"></div>`;
    panel().innerHTML = `
      <button data-action="flow-back" class="text-sky-700 mb-2">← Flows</button>
      <input data-flow-name value="${esc(e.name)}" class="${input} font-semibold mb-2" aria-label="Flow name">
      <div class="rounded border bg-slate-50 p-2 mb-2">
        <div class="text-xs text-slate-500 mb-1">Drag into the flow, or tap to add at the end. Press and hold ⋮⋮ to reorder.</div>
        <div class="flex flex-wrap gap-1 mb-1.5">
          <button draggable="true" data-palette='${esc(JSON.stringify({ title: "New task" }))}' class="px-2 py-1 rounded border border-dashed border-slate-400 bg-white text-xs cursor-grab">＋ Blank task</button>
          <button draggable="true" data-palette='${esc(JSON.stringify({ kind: "pause", title: "Pause" }))}' class="px-2 py-1 rounded border border-dashed border-amber-500 bg-amber-50 text-xs cursor-grab">⏸ Pause</button>
        </div>
        <input data-flow-search placeholder="Find a skill to add" class="${input} text-xs" aria-label="Find a skill">
        <div id="flow-palette" class="flex flex-wrap gap-1 mt-1.5">${paletteHtml()}</div>
      </div>
      ${problems(e.steps).length && e.steps.length ? `<p class="text-xs text-red-700 mb-1">${esc(problems(e.steps).join(" "))}</p>` : ""}
      <div id="flow-chain">
        ${e.steps.length ? "" : '<p class="text-slate-500 text-xs mb-1">Drop the first task here.</p>'}
        ${zone(0)}
        ${e.steps.map((s, i) => `${nodeHtml(s, i)}${i < e.steps.length - 1 ? `<div class="text-center text-slate-400 leading-none" aria-hidden="true">${s.app !== e.steps[i + 1].app || s.assignee !== e.steps[i + 1].assignee ? '<span class="text-sky-700 text-[10px]">⇣ handoff</span>' : "↓"}</div>` : ""}${zone(i + 1)}`).join("")}
      </div>
      <div class="flex gap-1 mt-2">
        <button data-action="flow-save" class="${btnPrimary} flex-1">${e.dirty ? "Save" : "Saved"}</button>
        <button data-action="flow-run" data-id="${e.id}" class="${btn}" ${e.dirty ? "disabled title='Save first'" : ""}>▶ Run</button>
      </div>`;
  }

  function nodeHtml(s, i) {
    const open = st.open === s.id, pause = isPause(s);
    return `<div draggable="true" data-node="${esc(s.id)}" class="border rounded p-2 ${pause ? "bg-amber-50 border-dashed border-amber-500" : "bg-white"} ${open ? "ring-2 ring-sky-600" : ""}">
      <div class="flex gap-1.5 items-start">
        <button data-action="flow-toggle" data-id="${esc(s.id)}" class="flex-1 text-left flex gap-1.5 items-start" aria-expanded="${open}">
          <span class="shrink-0 w-5 h-5 rounded-full ${pause ? "bg-amber-600" : "bg-slate-900"} text-white text-[10px] grid place-items-center">${pause ? "⏸" : i + 1}</span>
          <span class="flex-1"><span class="font-medium">${esc(s.title)}</span><span class="block text-xs text-slate-500">${pause ? esc(pauseLabel(s)) : `${appBadge(s.app)} ${esc(whoLabel(s.assignee))}${s.skill_name ? " · 📘 skill" : ""}`}</span></span>
        </button>
        <button data-action="flow-remove" data-id="${esc(s.id)}" class="text-slate-400 hover:text-red-700 px-1" aria-label="Delete ${esc(s.title)}" title="Delete">✕</button>
        <span data-grip="${esc(s.id)}" class="text-slate-400 px-1 cursor-grab select-none" style="touch-action:none" aria-hidden="true" title="Drag, or press and hold, to move">⋮⋮</span>
      </div>
      ${open ? `<div class="mt-2 space-y-1.5 text-xs" data-node-form="${esc(s.id)}">
        <input name="title" value="${esc(s.title)}" class="${input}" aria-label="Title">
        ${pause ? `<div class="flex gap-1"><select name="pause_mode" class="${input}" aria-label="Pause until"><option value="manual" ${s.pause_mode !== "timer" ? "selected" : ""}>Until someone resumes it</option><option value="timer" ${s.pause_mode === "timer" ? "selected" : ""}>For a set time</option></select>
            ${s.pause_mode === "timer" ? `<input name="pause_minutes" type="number" min="1" max="10080" value="${esc(s.pause_minutes || 30)}" class="${input} w-24" aria-label="Minutes">` : ""}</div>`
          : `<div class="flex gap-1"><select name="app" class="${input}" aria-label="App">${LANES.map((l) => `<option ${l === s.app ? "selected" : ""}>${l}</option>`).join("")}</select>
          <select name="assignee" class="${input}" aria-label="Who">${(st.who || []).map((w) => `<option value="${esc(w.value)}" ${w.value === s.assignee ? "selected" : ""}>${esc(w.label)}</option>`).join("")}</select></div>`}
        <textarea name="instructions" rows="2" class="${input}" placeholder="${pause ? "Note" : "Instructions"}" aria-label="Instructions">${esc(s.instructions || "")}</textarea>
        <div class="flex gap-1"><button data-action="flow-nudge" data-id="${esc(s.id)}" data-by="-1" class="${btn} text-xs" aria-label="Move up">↑</button><button data-action="flow-nudge" data-id="${esc(s.id)}" data-by="1" class="${btn} text-xs" aria-label="Move down">↓</button>
          ${!pause && st.edit.id && !st.edit.dirty ? `<button data-action="flow-run-from" data-index="${i}" class="${btn} text-xs ml-auto">▶ Run from here</button>` : ""}</div>
      </div>` : ""}
    </div>`;
  }

  function paletteHtml() {
    return st.palette.map((k) => `<button draggable="true" data-palette='${esc(JSON.stringify({ name: k.name, title: k.title, apps: k.apps }))}' class="px-2 py-1 rounded border bg-white text-xs cursor-grab" title="${esc(k.description || "")}">📘 ${esc(k.title)}</button>`).join("");
  }

  const change = (steps) => { st.edit.steps = steps; st.edit.dirty = true; renderEdit(); };

  // ---------- running ----------
  function renderRun() {
    const r = st.run;
    const cur = r.steps[r.current_index];
    const active = ["running", "on_hold"].includes(r.status);
    const nextI = r.steps.findIndex((s, i) => i > r.current_index && s.state === "pending");
    panel().innerHTML = `
      <button data-action="flow-back" class="text-sky-700 mb-2">← Flows</button>
      <h2 class="text-base font-semibold">${esc(r.flow)}</h2>
      <div class="text-xs mb-2 ${r.status === "on_hold" ? "text-amber-800 font-semibold" : "text-slate-500"}">${r.status === "on_hold" ? "⏸ Run on hold" : active ? `Now: ${isPause(cur) ? "paused" : `task ${r.current_index + 1}`}` : esc(r.status)}</div>
      ${r.owner && active ? `<div class="flex gap-1 mb-2">${r.status === "on_hold" ? `<button data-action="flow-release" class="${btnPrimary} text-xs">▶ Resume run</button>` : `<button data-action="flow-hold" class="${btn} text-xs">⏸ Pause run</button>`}</div>` : ""}
      <ol class="space-y-1 mb-2">${r.steps.map((s, i) => {
        const now = i === r.current_index && active;
        const mark = s.state === "done" ? "✓" : s.state === "skipped" ? "–" : now ? (s.state === "paused" ? "⏸" : "▶") : isPause(s) ? "⏸" : "○";
        return `<li class="border rounded p-1.5 ${now ? "border-sky-500 bg-sky-50 ring-2 ring-sky-300" : s.state === "done" ? "border-emerald-300 bg-emerald-50" : s.state === "skipped" ? "opacity-50" : isPause(s) ? "border-dashed border-amber-400" : ""}">
          <div class="flex gap-1.5"><span>${mark}</span><span class="flex-1"><span class="font-medium">${isPause(s) ? "" : `${i + 1}. `}${esc(s.title)}${now ? ' <span class="text-sky-700 text-xs font-semibold">running now</span>' : ""}</span>
          <span class="block text-xs text-slate-500">${isPause(s) ? esc(pauseLabel(s)) : `${appBadge(s.app)} ${esc(s.assignee)}`}${s.note ? ` · ${esc(s.note)}` : ""}</span>
          ${r.owner && active ? `<span class="flex gap-1 mt-1">${!now && !isPause(s) ? `<button data-action="flow-jump" data-index="${i}" class="text-xs text-sky-700 hover:underline">Deploy now</button>` : ""}
            ${["pending", "ready", "paused"].includes(s.state) ? `<button data-action="flow-skip" data-index="${i}" class="text-xs text-slate-600 hover:underline">Skip</button>` : ""}
            ${now && s.state === "paused" ? `<button data-action="flow-resume" data-index="${i}" class="text-xs text-amber-800 font-semibold hover:underline">▶ Resume</button>` : ""}
            ${i >= r.current_index ? `<button data-action="flow-insert-pause" data-index="${i}" class="text-xs text-slate-600 hover:underline">+ Pause after</button>` : ""}</span>` : ""}</span></div></li>`;
      }).join("")}</ol>
      ${r.mine && cur && r.status === "running" ? `<form data-form="flow-complete" class="rounded border p-2 space-y-1.5">
          <div class="font-medium">Your turn: ${esc(cur.title)}</div>
          ${cur.app !== "Agent" && cur.app !== host() ? `<p class="text-xs text-amber-800">This task is in ${esc(cur.app)}; it's also waiting in the add-in there.</p>` : ""}
          <textarea name="note" rows="2" class="${input}" placeholder="What you did, or where the output is"></textarea>
          <button class="${btnPrimary} w-full">Done: hand off ${nextI >= 0 ? (isPause(r.steps[nextI]) ? "to the pause" : `to task ${nextI + 1} (${esc(r.steps[nextI].app)})`) : "and finish"}</button>
        </form>` : active && cur && !isPause(cur) && r.status === "running" ? `<p class="text-xs text-slate-500">Waiting on ${esc(cur.assignee)}.</p>` : ""}
      <button data-action="open-url" data-url="${esc(r.url)}" class="${btn} mt-2 w-full">Open the process map</button>`;
  }

  // ---------- events (called from the pane's handlers) ----------
  async function onAction(a, t) {
    if (a === "flow-new") { await loadWho(); st.edit = { id: null, name: "New flow", steps: [], dirty: true }; st.view = "edit"; return renderEdit(); }
    if (a === "flow-template") { const f = await api.createFlow({ template: t.dataset.key }); await loadWho(); st.edit = { ...f, dirty: false }; st.view = "edit"; flash(`Created “${f.name}”. Drag to reorder; tap a task to edit it.`); return rerender(); }
    if (a === "flow-edit") { await loadWho(); const f = await api.flow(t.dataset.id); st.edit = { ...f, dirty: false }; st.view = "edit"; return renderEdit(); }
    if (a === "flow-run") { const r = await api.startFlow(t.dataset.id); st.run = r; st.view = "run"; flash("Started. Task 1 is ready."); return rerender(); }
    if (a === "flow-open-run") { st.run = await api.flowRun(t.dataset.id); st.view = "run"; return renderRun(); }
    if (a === "flow-back") { if (st.edit?.dirty && st.view === "edit" && !confirm("Leave without saving?")) return; st.view = "list"; st.edit = null; return render(); }
    if (["flow-jump", "flow-skip", "flow-resume", "flow-hold", "flow-release", "flow-insert-pause"].includes(a)) {
      const i = Number(t.dataset.index), id = st.run.id;
      st.run = a === "flow-jump" ? await api.flowRunAct(id, "jump", { step: i })
        : a === "flow-skip" ? await api.flowRunAct(id, "skip", { step: i })
        : a === "flow-resume" ? await api.flowRunAct(id, "resume", { step: i })
        : a === "flow-insert-pause" ? await api.flowRunAct(id, "insert", { after: i, kind: "pause", pause_mode: "manual", title: "Pause" })
        : await api.flowRunAct(id, a === "flow-hold" ? "hold" : "release", {});
      return renderRun();
    }
    if (a === "flow-run-from") { const r = await api.startFlow(st.edit.id, Number(t.dataset.index)); st.run = r; st.view = "run"; flash(`Started at task ${Number(t.dataset.index) + 1}.`); return rerender(); }
    if (a === "flow-toggle") { st.open = st.open === t.dataset.id ? null : t.dataset.id; return renderEdit(); }
    if (a === "flow-remove") return change(remove(st.edit.steps, t.dataset.id));
    if (a === "flow-nudge") { const i = st.edit.steps.findIndex((s) => s.id === t.dataset.id); return change(move(st.edit.steps, t.dataset.id, i + Number(t.dataset.by))); }
    if (a === "flow-save") {
      const errs = problems(st.edit.steps);
      if (errs.length) { flash(errs.join(" "), "error"); return rerender(); }
      const body = { name: st.edit.name, steps: st.edit.steps };
      const f = st.edit.id ? await api.updateFlow(st.edit.id, body) : await api.createFlow(body);
      st.edit = { ...f, dirty: false }; flash("Saved."); return rerender();
    }
    return false;
  }

  function onClick(ev) { // tap a palette chip: add at the end
    const p = ev.target.closest("[data-palette]");
    if (!p || st.view !== "edit") return false;
    change(insertAt(st.edit.steps, st.edit.steps.length, stepFrom(JSON.parse(p.dataset.palette))));
    return true;
  }

  async function onSubmit(f, data) {
    if (f.dataset.form !== "flow-complete") return false;
    st.run = await api.completeFlowStep(st.run.id, st.run.current_index, { note: data.note });
    flash(st.run.status === "completed" ? "Done: every task is complete." : `Handed off to task ${st.run.current_index + 1}: ${st.run.steps[st.run.current_index].title} (${st.run.steps[st.run.current_index].app}).`);
    rerender();
    return true;
  }

  function onInput(ev) {
    if (st.view !== "edit") return;
    if (ev.target.matches("[data-flow-name]")) { st.edit.name = ev.target.value; st.edit.dirty = true; return; }
    if (ev.target.matches("[data-flow-search]")) {
      clearTimeout(st.searchTimer);
      const q = ev.target.value.trim();
      st.searchTimer = setTimeout(async () => {
        st.palette = q ? (await api.skills(q, "", "", "").catch(() => [])).slice(0, 8) : [];
        const el = document.getElementById("flow-palette"); if (el) el.innerHTML = paletteHtml();
      }, 250);
      return;
    }
    const form = ev.target.closest("[data-node-form]");
    if (form && ev.target.name) {
      const n = ev.target.name, v = n === "pause_minutes" ? Number(ev.target.value) : ev.target.value;
      st.edit.steps = update(st.edit.steps, form.dataset.nodeForm, { [n]: v, ...(n === "pause_mode" && v === "timer" ? { pause_minutes: 30 } : {}) });
      st.edit.dirty = true;
      if (n === "pause_mode" && ev.type === "change") renderEdit();
    }
  }

  // Drag and drop: palette → a gap, or a node → another gap.
  function onDragStart(ev) {
    const n = ev.target.closest?.("[data-node]"), p = ev.target.closest?.("[data-palette]");
    if (!n && !p) return;
    ev.dataTransfer.setData("text/plain", JSON.stringify(n ? { node: n.dataset.node } : { palette: JSON.parse(p.dataset.palette) }));
    ev.dataTransfer.effectAllowed = n ? "move" : "copy";
  }
  function onDragOver(ev) {
    const z = ev.target.closest?.("[data-drop]");
    if (!z) return;
    ev.preventDefault();
    document.querySelectorAll(".flow-drop").forEach((d) => d.classList.remove("bg-sky-500", "h-6"));
    z.classList.add("bg-sky-500", "h-6");
  }
  function onDrop(ev) {
    const z = ev.target.closest?.("[data-drop]");
    if (!z || st.view !== "edit") return;
    ev.preventDefault();
    let d; try { d = JSON.parse(ev.dataTransfer.getData("text/plain")); } catch { return; }
    const gap = Number(z.dataset.drop);
    if (d.palette) { const s = stepFrom(d.palette); st.open = s.id; change(insertAt(st.edit.steps, gap, s)); }
    else if (d.node) { const from = st.edit.steps.findIndex((s) => s.id === d.node); change(move(st.edit.steps, d.node, from < gap ? gap - 1 : gap)); }
  }

  // Touch screens: press and hold a task (or drag its ⋮⋮ grip) to pick it up, slide to a gap, let go.
  function onPointerDown(ev) {
    if (st.view !== "edit" || ev.pointerType === "mouse") return;
    const node = ev.target.closest?.("[data-node]");
    if (!node || ev.target.closest("input,select,textarea,[data-action=flow-remove]")) return;
    const grip = ev.target.closest("[data-grip]");
    const id = node.dataset.node, x0 = ev.clientX, y0 = ev.clientY;
    const startDrag = () => {
      st.touch = { id, node };
      node.classList.add("opacity-60", "ring-2", "ring-sky-500");
      try { node.setPointerCapture(ev.pointerId); } catch { /* not capturable */ }
      navigator.vibrate?.(15);
    };
    if (grip) { ev.preventDefault(); startDrag(); return; }
    st.holdTimer = setTimeout(startDrag, HOLD_MS);
    st.holdStart = { x0, y0 };
  }
  function zoneAt(x, y) {
    const zones = [...document.querySelectorAll("[data-drop]")];
    let best = null, dist = Infinity;
    zones.forEach((z) => { const r = z.getBoundingClientRect(); const d = Math.abs((r.top + r.bottom) / 2 - y); if (d < dist && x >= r.left - 40 && x <= r.right + 40) { dist = d; best = z; } });
    return best;
  }
  function onPointerMove(ev) {
    if (st.holdTimer && st.holdStart && Math.hypot(ev.clientX - st.holdStart.x0, ev.clientY - st.holdStart.y0) > 8) { clearTimeout(st.holdTimer); st.holdTimer = null; }
    if (!st.touch) return;
    ev.preventDefault();
    document.querySelectorAll(".flow-drop").forEach((d) => d.classList.remove("bg-sky-500", "h-6"));
    zoneAt(ev.clientX, ev.clientY)?.classList.add("bg-sky-500", "h-6");
  }
  function onPointerUp(ev) {
    clearTimeout(st.holdTimer); st.holdTimer = null;
    if (!st.touch) return;
    const z = zoneAt(ev.clientX, ev.clientY), id = st.touch.id;
    st.touch = null;
    if (!z) return renderEdit();
    const gap = Number(z.dataset.drop), from = st.edit.steps.findIndex((s) => s.id === id);
    change(move(st.edit.steps, id, from < gap ? gap - 1 : gap));
  }

  // A flow task arrived for this app: open the run.
  async function showTask(task) {
    st.run = await api.flowRun(task.flow_run_id); st.view = "run";
  }

  return { render, onAction, onClick, onSubmit, onInput, onDragStart, onDragOver, onDrop, onPointerDown, onPointerMove, onPointerUp, showTask };
}
