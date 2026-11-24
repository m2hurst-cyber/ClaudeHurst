import { test } from "node:test";
import assert from "node:assert/strict";
import { stepFrom, insertAt, move, remove, update, gapIndex, layout, problems, LANES, shiftLane, pauseLabel, isPause } from "addin/flow_model";

const s = (id, app = "Excel", assignee = "me") => ({ id, title: id, app, assignee });

test("palette items become steps; skills land in their app's lane", () => {
  const a = stepFrom({ name: "charts-to-ppt-appendix", title: "Appendix", apps: ["Excel", "PowerPoint"] });
  assert.equal(a.app, "Excel");
  assert.equal(a.skill_name, "charts-to-ppt-appendix");
  assert.equal(stepFrom({}, "Word").app, "Word");
  assert.equal(stepFrom({}).app, "Agent");
  assert.notEqual(stepFrom({}).id, stepFrom({}).id);
});

test("insert, move across lanes, remove, update", () => {
  let st = [s("a"), s("b"), s("c")];
  st = insertAt(st, 1, s("x", "Word"));
  assert.deepEqual(st.map((x) => x.id), ["a", "x", "b", "c"]);
  st = move(st, "a", 3, "PowerPoint");
  assert.deepEqual(st.map((x) => x.id), ["x", "b", "c", "a"]);
  assert.equal(st[3].app, "PowerPoint");
  st = move(st, "c", 0);
  assert.deepEqual(st.map((x) => x.id), ["c", "x", "b", "a"]);
  assert.equal(st[0].app, "Excel", "moving without a lane keeps the app");
  st = update(remove(st, "x"), "b", { title: "Clean data" });
  assert.deepEqual(st.map((x) => x.title), ["c", "Clean data", "a"]);
  assert.equal(insertAt(Array.from({ length: 50 }, (_, i) => s(`n${i}`)), 0, s("over")).length, 50);
});

test("drop position → gap, and the process map layout marks handoffs", () => {
  assert.equal(gapIndex([100, 200, 300], 50), 0);
  assert.equal(gapIndex([100, 200, 300], 250), 2);
  assert.equal(gapIndex([100, 200, 300], 999), 3);
  const { nodes, edges } = layout([s("a"), s("b"), s("c", "Agent", "agent:4"), s("d", "PowerPoint")]);
  assert.deepEqual(nodes.map((n) => [n.col, n.row]), [[0, 0], [1, 0], [2, LANES.indexOf("Agent")], [3, LANES.indexOf("PowerPoint")]]);
  assert.deepEqual(edges.map((e) => e.crossing), [false, true, true]);
  assert.deepEqual(problems([]), ["Add at least one task."]);
  assert.deepEqual(problems([{ id: "a", title: " " }]), ["Task 1 needs a title."]);
});

test("pauses: palette item, labels, no handoff across a pause, timer needs minutes; lanes by keyboard", () => {
  const p = stepFrom({ kind: "pause" }, "Excel");
  assert.ok(isPause(p));
  assert.equal(pauseLabel(p), "Wait until resumed");
  assert.equal(pauseLabel({ pause_mode: "timer", pause_minutes: 90 }), "Wait 90 min");
  assert.equal(pauseLabel({ pause_mode: "timer", pause_minutes: 120 }), "Wait 2 hours");
  assert.equal(pauseLabel({ pause_mode: "timer", pause_minutes: 2880 }), "Wait 2 days");
  const { edges } = layout([s("a", "Excel"), p, s("b", "Word")]);
  assert.deepEqual(edges.map((e) => e.crossing), [false, false]);
  assert.deepEqual(problems([{ ...p, pause_mode: "timer" }]), ["Pause 1 needs a number of minutes."]);
  assert.equal(shiftLane([s("a", "Excel")], "a", 1)[0].app, "Word");
  assert.equal(shiftLane([s("a", "Excel")], "a", -1)[0].app, "Excel");
});
