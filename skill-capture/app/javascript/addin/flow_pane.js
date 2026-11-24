// The add-in's Flows tab: a vertical flowchart you build by drag and drop (skills or blank tasks from the
// palette, tasks dragged to reorder), then run: each task happens in order and hands off to the next,
// in the app or agent that does it.
import { LANES, stepFrom, insertAt, move, remove, update, problems } from "addin/flow_model";

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
        <div class="text-xs text-slate-500 mb-1">Drag into the flow, or tap to add at the end</div>
        <div class="flex flex-wrap gap-1 mb-1.5">
          <button draggable="true" data-palette='${esc(JSON.stringify({ title: "New task" }))}' class="px-2 py-1 rounded border border-dashed border-slate-400 bg-white text-xs cursor-grab">＋ Blank task</button>
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
    const open = st.open === s.id;
    return `<div draggable="true" data-node="${esc(s.id)}" class="border rounded bg-white p-2 ${open ? "ring-2 ring-sky-600" : ""} cursor-grab">
      <button data-action="flow-toggle" data-id="${esc(s.id)}" class="w-full text-left flex gap-1.5 items-start" aria-expanded="${open}">
        <span class="shrink-0 w-5 h-5 rounded-full bg-slate-900 text-white text-[10px] grid place-items-center">${i + 1}</span>
        <span class="flex-1"><span class="font-medium">${esc(s.title)}</span><span class="block text-xs text-slate-500">${appBadge(s.app)} ${esc(whoLabel(s.assignee))}${s.skill_name ? " · 📘 skill" : ""}</span></span>
        <span class="text-slate-400" aria-hidden="true">⋮⋮</span>
      </button>
      ${open ? `<div class="mt-2 space-y-1.5 text-xs" data-node-form="${esc(s.id)}">
        <input name="title" value="${esc(s.title)}" class="${input}" aria-label="Title">
        <div class="flex gap-1"><select name="app" class="${input}" aria-label="App">${LANES.map((l) => `<option ${l === s.app ? "selected" : ""}>${l}</option>`).join("")}</select>
          <select name="assignee" class="${input}" aria-label="Who">${(st.who || []).map((w) => `<option value="${esc(w.value)}" ${w.value === s.assignee ? "selected" : ""}>${esc(w.label)}</option>`).join("")}</select></div>
        <textarea name="instructions" rows="2" class="${input}" placeholder="Instructions" aria-label="Instructions">${esc(s.instructions || "")}</textarea>
        <div class="flex gap-1"><button data-action="flow-nudge" data-id="${esc(s.id)}" data-by="-1" class="${btn} text-xs" aria-label="Move up">↑</button><button data-action="flow-nudge" data-id="${esc(s.id)}" data-by="1" class="${btn} text-xs" aria-label="Move down">↓</button>
          <button data-action="flow-remove" data-id="${esc(s.id)}" class="${btn} text-xs text-red-700 ml-auto">Remove</button></div>
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
    panel().innerHTML = `
      <button data-action="flow-back" class="text-sky-700 mb-2">← Flows</button>
      <h2 class="text-base font-semibold">${esc(r.flow)}</h2>
      <div class="text-xs text-slate-500 mb-2">${r.status === "running" ? `Task ${r.current_index + 1} of ${r.steps.length}` : esc(r.status)}</div>
      <ol class="space-y-1 mb-2">${r.steps.map((s, i) => `<li class="border rounded p-1.5 ${s.state === "ready" ? "border-amber-400 bg-amber-50" : s.state === "done" ? "border-emerald-300 bg-emerald-50" : ""}">
        <div class="flex gap-1.5"><span>${s.state === "done" ? "✓" : s.state === "ready" ? "▶" : "○"}</span><span class="flex-1"><span class="font-medium">${i + 1}. ${esc(s.title)}</span>
        <span class="block text-xs text-slate-500">${appBadge(s.app)} ${esc(s.assignee)}${s.note ? ` · ${esc(s.note)}` : ""}</span></span></div></li>`).join("")}</ol>
      ${r.mine && cur ? `<form data-form="flow-complete" class="rounded border p-2 space-y-1.5">
          <div class="font-medium">Your turn: ${esc(cur.title)}</div>
          ${cur.app !== "Agent" && cur.app !== host() ? `<p class="text-xs text-amber-800">This task is in ${esc(cur.app)}; it's also waiting in the add-in there.</p>` : ""}
          <textarea name="note" rows="2" class="${input}" placeholder="What you did, or where the output is"></textarea>
          <button class="${btnPrimary} w-full">Done: hand off ${r.current_index + 1 < r.steps.length ? `to task ${r.current_index + 2} (${esc(r.steps[r.current_index + 1].app)})` : "and finish"}</button>
        </form>` : r.status === "running" ? `<p class="text-xs text-slate-500">Waiting on ${esc(cur?.assignee || "")}.</p>` : ""}
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
    if (form && ev.target.name) { st.edit.steps = update(st.edit.steps, form.dataset.nodeForm, { [ev.target.name]: ev.target.value }); st.edit.dirty = true; }
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

  // A flow task arrived for this app: open the run.
  async function showTask(task) {
    st.run = await api.flowRun(task.flow_run_id); st.view = "run";
  }

  return { render, onAction, onClick, onSubmit, onInput, onDragStart, onDragOver, onDrop, showTask };
}
