// Pure operations on a flow's ordered steps, shared by the add-in's vertical flowchart and the console's
// process map. A step: { id, title, app, assignee, skill_name?, instructions? }. Order = execution order.

export const LANES = ["Excel", "Word", "PowerPoint", "Outlook", "Teams", "Agent"];
export const MAX_STEPS = 50;

let seq = 0;
export const newId = () => `${Date.now().toString(36).slice(-5)}${(seq++).toString(36)}${Math.random().toString(36).slice(2, 5)}`.replace(/[^a-z0-9]/g, "").slice(0, 16);

export const isPause = (s) => s?.kind === "pause";

// "Wait 30 minutes", "Wait until resumed"
export function pauseLabel(s) {
  if (s.pause_mode !== "timer") return "Wait until resumed";
  const m = Number(s.pause_minutes) || 0;
  return `Wait ${m >= 1440 && m % 1440 === 0 ? `${m / 1440} day${m === 1440 ? "" : "s"}` : m >= 60 && m % 60 === 0 ? `${m / 60} hour${m === 60 ? "" : "s"}` : `${m} min`}`;
}

// A new step from a palette item: a blank task, a pause, or a skill (its app guessed from the skill's apps).
export function stepFrom(item = {}, lane) {
  if (item.kind === "pause") return { id: newId(), kind: "pause", title: item.title || "Pause", app: lane || "Agent", assignee: "me", pause_mode: item.pause_mode || "manual", ...(item.pause_minutes ? { pause_minutes: item.pause_minutes } : {}) };
  const app = lane || (item.apps || []).find((a) => LANES.includes(a)) || "Agent";
  return { id: newId(), title: item.title || "New task", app, assignee: item.assignee || "me", ...(item.name ? { skill_name: item.name } : {}), ...(item.instructions ? { instructions: item.instructions } : {}) };
}

const clamp = (i, lo, hi) => Math.max(lo, Math.min(hi, i));

export function insertAt(steps, index, step) {
  if (steps.length >= MAX_STEPS) return steps;
  const out = steps.slice();
  out.splice(clamp(index, 0, out.length), 0, step);
  return out;
}

// Move a step to a new position (index in the list without it), optionally into another lane.
export function move(steps, id, toIndex, lane) {
  const from = steps.findIndex((s) => s.id === id);
  if (from < 0) return steps;
  const out = steps.slice();
  const [s] = out.splice(from, 1);
  out.splice(clamp(toIndex, 0, out.length), 0, lane && LANES.includes(lane) ? { ...s, app: lane } : s);
  return out;
}

export const remove = (steps, id) => steps.filter((s) => s.id !== id);

// Keyboard: move a step one lane up or down.
export function shiftLane(steps, id, by) {
  return steps.map((s) => (s.id === id ? { ...s, app: LANES[Math.max(0, Math.min(LANES.length - 1, LANES.indexOf(s.app) + by))] } : s));
}
export const update = (steps, id, patch) => steps.map((s) => (s.id === id ? { ...s, ...patch } : s));

// Where a drop lands: the gap index from the drop's x (process map) or y (flowchart), given the centres
// of the existing nodes in order.
export function gapIndex(centres, pos) {
  const i = centres.findIndex((c) => pos < c);
  return i < 0 ? centres.length : i;
}

// Process map layout: one column per step (order), one row per lane; plus the handoffs, marking where
// the work crosses to another app or agent.
export function layout(steps) {
  const nodes = steps.map((s, i) => ({ id: s.id, col: i, row: Math.max(0, LANES.indexOf(s.app)), step: s }));
  const edges = nodes.slice(1).map((n, i) => {
    const a = nodes[i].step, b = n.step;
    return { from: nodes[i].id, to: n.id, crossing: !isPause(a) && !isPause(b) && (a.app !== b.app || a.assignee !== b.assignee) };
  });
  return { nodes, edges, lanes: LANES };
}

export function problems(steps) {
  const out = [];
  if (!steps.length) out.push("Add at least one task.");
  if (steps.length > MAX_STEPS) out.push(`At most ${MAX_STEPS} tasks.`);
  steps.forEach((s, i) => {
    if (!String(s.title || "").trim()) out.push(`Task ${i + 1} needs a title.`);
    if (isPause(s) && s.pause_mode === "timer" && !(Number(s.pause_minutes) >= 1)) out.push(`Pause ${i + 1} needs a number of minutes.`);
  });
  return out;
}
