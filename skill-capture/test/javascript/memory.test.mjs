import { test } from "node:test";
import assert from "node:assert/strict";

const store = new Map();
globalThis.localStorage = { getItem: (k) => store.get(k) ?? null, setItem: (k, v) => store.set(k, v), removeItem: (k) => store.delete(k) };
const { memory } = await import("addin/memory");

const bundle = (name, version = 1) => ({
  name, version, title: `Title ${name}`, skill_md: `---\nname: ${name}\n---\n\n# Steps\n1. Do it`,
  directions: [{ key: `junction:${name}`, title: "Intersection", markdown: "Take the Excel road." }],
  resources: [{ key: `resource:x/${name}`, name: "Template", url: "/r/1" }],
});

test("adds newest first, replaces older copies, removes and clears", () => {
  memory.clear();
  memory.add(bundle("a"), "Rae");
  memory.add(bundle("b"));
  memory.add(bundle("a", 2));
  assert.deepEqual(memory.list().map((m) => [m.name, m.version]), [["a", 2], ["b", 1]]);
  assert.equal(memory.get("b").from, null);
  memory.remove("b");
  assert.deepEqual(memory.list().map((m) => m.name), ["a"]);
  memory.clear();
  assert.equal(memory.list().length, 0);
});

test("asContext gives an AI the skill without frontmatter, then directions and resources", () => {
  memory.add(bundle("a"));
  const ctx = memory.asContext("a");
  assert.ok(ctx.startsWith("# Steps"));
  assert.match(ctx, /Take the Excel road\./);
  assert.match(ctx, /- Template \(resource:x\/a\): \/r\/1/);
});

test("is exposed for other add-in code", () => {
  assert.equal(globalThis.window?.SkillCaptureMemory ?? memory, memory);
});
