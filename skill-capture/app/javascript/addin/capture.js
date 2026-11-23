import { VOCABULARY, SUPERSEDES, SUPERSEDE_WINDOW_MS, HOST_PREFIX } from "addin/vocabulary";

// Office-independent capture engine: dedupes, batches and sends steps, and keeps the
// live list for "Record a procedure". Office event wiring lives in office_hosts.js.
export function createCapture({ host, send, now = () => Date.now(), uuid = () => crypto.randomUUID(),
                                batchSize = 50, domain = null }) {
  const session = uuid();
  let capturing = false;
  let queue = [];
  let last = null;          // last step queued for sending (for de-duplication)
  let recording = null;     // { steps: [], startedAt }
  const listeners = new Set();

  const label = (action) => VOCABULARY[action] || action;
  const emit = () => listeners.forEach((fn) => fn(state()));

  function state() {
    return { capturing, queued: queue.length, recording: recording ? { steps: recording.steps.slice() } : null };
  }

  function pushRecording(step) {
    if (!recording) return;
    const steps = recording.steps;
    const prev = steps[steps.length - 1];
    if (prev && prev.action === step.action) return;
    const supersedes = SUPERSEDES[step.action] || [];
    if (prev && supersedes.includes(prev.action) && step.t - prev.t <= SUPERSEDE_WINDOW_MS) steps.pop();
    steps.push(step);
  }

  // Record one observed step (a key from VOCABULARY).
  function record(action) {
    const t = now();
    const step = { action, label: label(action), t };
    pushRecording(step);

    if (capturing) {
      const supersedes = SUPERSEDES[action] || [];
      if (last && last.action === action) {
        // consecutive duplicate: the server would collapse it anyway
      } else if (last && supersedes.includes(last.action) && t - last.t <= SUPERSEDE_WINDOW_MS && queue.length &&
                 queue[queue.length - 1].action === last.action) {
        queue[queue.length - 1] = toEvent(step);
        last = step;
      } else {
        queue.push(toEvent(step));
        last = step;
      }
      if (queue.length >= batchSize) flush();
    }
    emit();
  }

  function toEvent(step) {
    const e = { action: step.action, label: step.label, session, occurred_at: new Date(step.t).toISOString(),
                context: { app: HOST_PREFIX[host] || "office" } };
    if (domain) e.domain = domain;
    return e;
  }

  async function flush() {
    if (!queue.length) return { sent: 0 };
    const batch = queue;
    queue = [];
    try {
      await send({ host, events: batch });
      emit();
      return { sent: batch.length };
    } catch (err) {
      queue = batch.concat(queue).slice(-1000); // keep for retry, bounded
      emit();
      throw err;
    }
  }

  return {
    session,
    record,
    flush,
    state,
    label,
    onChange(fn) { listeners.add(fn); return () => listeners.delete(fn); },
    setCapturing(on) { capturing = !!on; if (!capturing) { queue = []; last = null; } emit(); },
    setDomain(d) { domain = d || null; },
    startRecording() { recording = { steps: [], startedAt: now() }; emit(); },
    // Pick up a recording autosaved before the pane closed or crashed.
    restoreRecording(steps) {
      recording = { steps: (steps || []).filter((s) => s && s.action && s.label).map((s) => ({ action: s.action, label: s.label, t: now() })), startedAt: now() };
      emit();
    },
    addNote(step) { if (recording && step.label) { recording.steps.push({ ...step, t: now() }); emit(); } },
    removeStep(index) { if (recording) { recording.steps.splice(index, 1); emit(); } },
    stopRecording() {
      const steps = recording ? recording.steps.map(({ action, label }) => ({ action, label })) : [];
      recording = null;
      emit();
      return steps;
    },
  };
}
