import { test } from "node:test";
import assert from "node:assert/strict";
import { compile, runMacro } from "addin/macro_runner";

const fakeExcel = { run: async (fn) => fn({ workbook: { name: "Book1" } }) };

test("an approved macro runs against the document and reports what it did, with no tokens", async () => {
  const code = "async function run(context) { return `Tidied ${context.workbook.name}`; }";
  const r = await runMacro(code, { host: "Excel", excel: fakeExcel });
  assert.equal(r.note, "Tidied Book1");
  assert.ok(r.duration_ms >= 0);
});

test("a macro without run(context) is refused, and failures carry the script's own message", async () => {
  assert.throws(() => compile("const x = 1"), /no run\(context\) function/);
  await assert.rejects(runMacro("async function run(c) { throw new Error('no chart on this sheet'); }", { host: "Excel", excel: fakeExcel }), /no chart on this sheet/);
  await assert.rejects(runMacro("async function run(c) { return 1; }", { host: "Word", excel: fakeExcel }), /run in Excel/);
});
