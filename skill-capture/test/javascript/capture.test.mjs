import { test } from "node:test";
import assert from "node:assert/strict";
import { createCapture } from "addin/capture";
import { manualStep, slug, VOCABULARY, EXCEL_CHANGE_TYPES } from "addin/vocabulary";
import { renderMarkdown, toPlainSteps } from "addin/markdown";

function setup(opts = {}) {
  let t = Date.parse("2026-11-23T10:00:00Z");
  const sent = [];
  const cap = createCapture({ host: "Excel", send: async (p) => { if (opts.fail) throw new Error("offline"); sent.push(p); },
                              now: () => t, uuid: () => "sess-1", batchSize: opts.batchSize ?? 50, ...opts });
  return { cap, sent, tick: (ms) => { t += ms; } };
}

test("nothing is queued until capture is switched on", async () => {
  const { cap, sent } = setup();
  cap.record("excel.data.sorted");
  await cap.flush();
  assert.equal(sent.length, 0);
});

test("queues structural events with labels, session and app context, and drops consecutive duplicates", async () => {
  const { cap, sent, tick } = setup();
  cap.setCapturing(true);
  cap.record("excel.cells.edited"); tick(5000);
  cap.record("excel.cells.edited"); tick(5000);
  cap.record("excel.data.sorted");
  await cap.flush();
  assert.equal(sent.length, 1);
  assert.equal(sent[0].host, "Excel");
  assert.deepEqual(sent[0].events.map((e) => e.action), ["excel.cells.edited", "excel.data.sorted"]);
  const e = sent[0].events[1];
  assert.deepEqual(Object.keys(e).sort(), ["action", "context", "label", "occurred_at", "session"]);
  assert.equal(e.label, "Sort data");
  assert.equal(e.session, "sess-1");
  assert.deepEqual(e.context, { app: "excel" });
  assert.equal(e.occurred_at, "2026-11-23T10:00:10.000Z");
});

test("a formula change replaces the generic cell edit fired for the same keystroke", async () => {
  const { cap, sent, tick } = setup();
  cap.setCapturing(true);
  cap.record("excel.cells.edited"); tick(200);
  cap.record("excel.formula.changed"); tick(10_000);
  cap.record("excel.cells.edited");
  await cap.flush();
  assert.deepEqual(sent[0].events.map((e) => e.action), ["excel.formula.changed", "excel.cells.edited"]);
});

test("but not when they are separate edits", async () => {
  const { cap, sent, tick } = setup();
  cap.setCapturing(true);
  cap.record("excel.cells.edited"); tick(5000);
  cap.record("excel.formula.changed");
  await cap.flush();
  assert.deepEqual(sent[0].events.map((e) => e.action), ["excel.cells.edited", "excel.formula.changed"]);
});

test("flushes automatically at the batch size and keeps events for retry when offline", async () => {
  const ok = setup({ batchSize: 2 });
  ok.cap.setCapturing(true);
  ok.cap.record("excel.rows.inserted");
  ok.cap.record("excel.data.sorted");
  await new Promise((r) => setTimeout(r, 0));
  assert.equal(ok.sent.length, 1);

  const off = setup({ fail: true });
  off.cap.setCapturing(true);
  off.cap.record("excel.rows.inserted");
  await assert.rejects(off.cap.flush());
  assert.equal(off.cap.state().queued, 1);
});

test("turning capture off discards anything not yet sent", () => {
  const { cap } = setup();
  cap.setCapturing(true);
  cap.record("excel.rows.inserted");
  cap.setCapturing(false);
  assert.equal(cap.state().queued, 0);
});

test("recording works without passive capture and mixes observed steps with typed notes", () => {
  const { cap, tick } = setup();
  cap.startRecording();
  cap.record("excel.cells.edited"); tick(100);
  cap.record("excel.formula.changed"); tick(5000);
  cap.addNote(manualStep("Excel", "Check totals match the bank statement!"));
  cap.record("excel.data.sorted");
  cap.record("excel.data.sorted");
  const steps = cap.stopRecording();
  assert.deepEqual(steps, [
    { action: "excel.formula.changed", label: "Enter or change a formula" },
    { action: "excel.step:check-totals-match-the-bank-statement", label: "Check totals match the bank statement!" },
    { action: "excel.data.sorted", label: "Sort data" },
  ]);
  assert.equal(cap.state().queued, 0, "recording alone sends nothing");
});

test("steps can be removed while recording", () => {
  const { cap } = setup();
  cap.startRecording();
  cap.record("excel.rows.inserted");
  cap.record("excel.data.sorted");
  cap.removeStep(0);
  assert.deepEqual(cap.stopRecording().map((s) => s.action), ["excel.data.sorted"]);
});

test("every key the add-in can emit is a valid server action key with a label", () => {
  const ACTION = /^[\w.:\-/#]{1,160}$/;
  for (const [k, label] of Object.entries(VOCABULARY)) { assert.match(k, ACTION); assert.ok(label); }
  for (const k of Object.values(EXCEL_CHANGE_TYPES)) assert.ok(VOCABULARY[k], k);
  assert.match(manualStep("Word", "Ask Legal (Jo) to sign off — today").action, ACTION);
  assert.equal(slug("   "), "step");
});

test("markdown renderer escapes HTML", () => {
  const html = renderMarkdown("# Title\n\n1. Run `macro`\n   _Action: x_\n- <script>alert(1)</script>\n> note **bold**");
  assert.match(html, /<h2[^>]*>Title<\/h2>/);
  assert.match(html, /<ol[^>]*>\n<li>Run <code[^>]*>macro<\/code>/);
  assert.ok(!html.includes("<script>"));
  assert.ok(html.includes("&lt;script&gt;"));
  assert.match(toPlainSteps({ title: "T", body: "## Steps\n1. **Do** it" }), /^T\n\nSteps\n1. Do it$/);
});
