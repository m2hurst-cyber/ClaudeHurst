import { test } from "node:test";
import assert from "node:assert/strict";
import { layout, roadPath, trafficWidth } from "route_map/layout";

const n = (id, area = "finance", kind = "skill") => ({ id, title: id, area, kind });

test("a chain is laid out left to right in journey order", () => {
  const { positions } = layout([n("c"), n("a"), n("b")], [{ from: "a", to: "b" }, { from: "b", to: "c" }]);
  assert.ok(positions.get("a").x < positions.get("b").x && positions.get("b").x < positions.get("c").x);
  assert.equal(positions.get("a").y, positions.get("c").y, "a straight chain stays on one row");
});

test("a branch runs parallel to its parent (same column, own row), not after it", () => {
  const { positions } = layout([n("start"), n("parent"), n("variant"), n("end")], [
    { from: "start", to: "parent", kind: "next" }, { from: "parent", to: "end", kind: "next" },
    { from: "start", to: "variant", kind: "next" }, { from: "variant", to: "end", kind: "next" },
    { from: "parent", to: "variant", kind: "branch" }]);
  assert.equal(positions.get("variant").x, positions.get("parent").x);
  assert.notEqual(positions.get("variant").y, positions.get("parent").y);
  assert.ok(positions.get("end").x > positions.get("variant").x);
});

test("a branch alone keeps the variant beside its parent", () => {
  const { positions } = layout([n("parent"), n("variant")], [{ from: "parent", to: "variant", kind: "branch" }]);
  assert.equal(positions.get("variant").x, positions.get("parent").x);
  assert.ok(!positions.get("variant").loose);
});

test("a skill reached by a long and a short route goes after the long one", () => {
  const { positions } = layout([n("a"), n("b"), n("c")], [{ from: "a", to: "b" }, { from: "b", to: "c" }, { from: "a", to: "c" }]);
  assert.ok(positions.get("c").x > positions.get("b").x);
});

test("loops don't hang the layout", () => {
  const { positions } = layout([n("a"), n("b"), n("c")], [{ from: "a", to: "b" }, { from: "b", to: "c" }, { from: "c", to: "a" }]);
  assert.equal(new Set([...positions.values()].map((p) => p.x)).size, 3);
});

test("separate networks stack vertically and roadless skills go to the grid at the end", () => {
  const { positions, looseStartY } = layout([n("a"), n("b"), n("x"), n("y"), n("solo")],
    [{ from: "a", to: "b" }, { from: "x", to: "y" }]);
  assert.notEqual(positions.get("a").y, positions.get("x").y);
  assert.ok(positions.get("solo").loose);
  assert.equal(positions.get("solo").y, looseStartY);
  assert.ok(looseStartY > Math.max(positions.get("a").y, positions.get("x").y));
});

test("edges to unknown nodes are ignored", () => {
  const { positions } = layout([n("a")], [{ from: "a", to: "ghost" }]);
  assert.equal(positions.size, 1);
});

test("road geometry and traffic widths", () => {
  assert.match(roadPath({ x: 0, y: 10 }, { x: 300, y: 50 }, 170), /^M170,10 C/);
  assert.equal(trafficWidth(0, 10), 3);
  assert.equal(trafficWidth(10, 10), 12);
  assert.ok(trafficWidth(2, 10) < trafficWidth(8, 10));
});

test("a branch with no road in of its own sits in its parent's column and rejoins to the right", () => {
  const nodes = ["a", "b", "c", "x"].map((id) => ({ id, title: id }));
  const edges = [{ from: "a", to: "b", kind: "next" }, { from: "b", to: "c", kind: "next" },
                 { from: "b", to: "x", kind: "branch" }, { from: "x", to: "c", kind: "next" }];
  const { positions } = layout(nodes, edges);
  assert.equal(positions.get("x").x, positions.get("b").x);
  assert.ok(positions.get("c").x > positions.get("x").x);
});
