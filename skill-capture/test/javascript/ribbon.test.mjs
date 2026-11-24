import { test } from "node:test";
import assert from "node:assert/strict";
import { registerRibbon, showPane, RIBBON_ACTIONS } from "addin/ribbon";

test("ribbon buttons are associated with handlers, and every press completes, even when a handler fails", async () => {
  const fns = {};
  const office = { actions: { associate: (name, fn) => { fns[name] = fn; } } };
  const calls = [];
  const names = registerRibbon(office, {
    showMemory: async () => calls.push("memory"),
    openMap: async () => { throw new Error("offline"); },
  });
  assert.deepEqual(names, ["showMemory", "openMap"]);
  let completed = 0;
  const event = { completed: () => completed++ };
  const err = console.error; console.error = () => {};
  await fns.showMemory(event);
  await fns.openMap(event);
  console.error = err;
  assert.deepEqual(calls, ["memory"]);
  assert.equal(completed, 2);
});

test("without the shared runtime (older Office), nothing is registered and opening the pane is harmless", async () => {
  assert.deepEqual(registerRibbon({}, { showMemory: () => {} }), []);
  await showPane({});
  let shown = false;
  await showPane({ addin: { showAsTaskpane: async () => { shown = true; } } });
  assert.ok(shown);
  assert.ok(RIBBON_ACTIONS.includes("toggleCapture"));
});
