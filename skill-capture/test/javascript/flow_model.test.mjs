import { test } from "node:test";
import assert from "node:assert/strict";
import { stepFrom, insertAt, move, remove, update, gapIndex, layout, problems, LANES } from "addin/flow_model";

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
