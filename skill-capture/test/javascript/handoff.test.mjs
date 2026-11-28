import { test } from "node:test";
import assert from "node:assert/strict";

const store = new Map();
globalThis.localStorage = { getItem: (k) => store.get(k) ?? null, setItem: (k, v) => store.set(k, v), removeItem: (k) => store.delete(k) };
const { memory } = await import("addin/memory");
const { handOff, readHandoff, bundle, toXml, rows, NAMESPACE, SHEET } = await import("addin/handoff");

// A workbook just real enough to be wrong about: custom XML parts addressed by namespace,
// worksheets that can be added and deleted, and ranges that remember what was written.
function fakeExcel() {
  const book = { parts: [], sheets: [], writes: [] };
  const partsFor = (ns) => ({
    items: book.parts.filter((p) => p.ns === ns).map((p) => ({
      id: p.id,
      delete: () => { book.parts = book.parts.filter((x) => x !== p); },
      getXml: () => ({ value: p.xml })
    })),
    load: () => {}
  });
  const makeRange = (address) => ({
    address,
    set values(v) { book.writes.push({ address, values: v }); },
    format: { wrapText: null, font: {}, columnWidth: null }
  });
  const makeSheet = (name) => ({
    name,
    delete: () => { book.sheets = book.sheets.filter((s) => s.name !== name); },
    getRangeByIndexes: (r, c, rows_, cols) => makeRange(`R${r}C${c}:${rows_}x${cols}`),
    getRange: (a) => makeRange(a)
  });
  const context = {
    workbook: {
      customXmlParts: {
        getByNamespace: (ns) => partsFor(ns),
        add: (xml) => { book.parts.push({ id: `p${book.parts.length + 1}`, ns: NAMESPACE, xml }); }
      },
      worksheets: {
        get items() { return book.sheets; },
        load: () => {},
        add: (name) => { const s = makeSheet(name); book.sheets.push(s); return s; }
      }
    },
    sync: async () => {}
  };
  return { excel: { run: async (fn) => fn(context) }, book };
}

const skill = {
  name: "bill-the-job", version: 3, title: "Bill the job", content_hash: "a".repeat(64),
  skill_md: "---\nname: bill-the-job\n---\n\n# Bill the job\n1. Open the schedule of values\n2. Hold retainage",
  directions: [{ markdown: "Take the Excel road." }], resources: []
};

test("a bundle carries what is needed to say which skill was followed", () => {
  memory.clear(); memory.add(skill);
  const b = bundle("bill-the-job");
  assert.equal(b.skill, "bill-the-job");
  assert.equal(b.version, 3);
  assert.equal(b.content_hash, "a".repeat(64), "the hash travels, so a run can be tied back to a version");
  assert.ok(b.directions.includes("Hold retainage"));
  assert.ok(!b.directions.includes("---"), "frontmatter is not directions");
  assert.equal(bundle("not-in-memory"), null);
});

test("the XML escapes what would otherwise break the document", () => {
  memory.clear();
  memory.add({ ...skill, name: "x", title: "Fees < 5% & \"rising\"", skill_md: "# A <b> & more" });
  const xml = toXml(bundle("x"));
  assert.ok(xml.includes(`xmlns="${NAMESPACE}"`));
  assert.ok(xml.includes("Fees &lt; 5% &amp; \"rising\""));
  assert.ok(!xml.includes("<b>"), "angle brackets from the body must not become markup");
});

test("the sheet opens by saying what it is and that it can be deleted" , () => {
  memory.clear(); memory.add(skill);
  const r = rows(bundle("bill-the-job"));
  assert.match(r[0][0], /Directions for an AI assistant/);
  assert.match(r[0][0], /Safe to delete/);
  assert.match(r[1][0], /Bill the job · v3 · aaaaaaaaaaaa/, "which skill, which version, which bytes");
  assert.ok(r.some((row) => row[0].includes("Hold retainage")));
  assert.ok(r.every((row) => row.length === 1), "one column, so it is a block of text and not a table");
});

test("handing off writes both channels, and replaces rather than accumulates", async () => {
  memory.clear(); memory.add(skill);
  const { excel, book } = fakeExcel();

  const first = await handOff("bill-the-job", { excel });
  assert.deepEqual([first.xml, first.sheet], [true, true]);
  assert.equal(book.parts.length, 1);
  assert.deepEqual(book.sheets.map((s) => s.name), [SHEET]);

  await handOff("bill-the-job", { excel });
  assert.equal(book.parts.length, 1, "a second handoff replaces the first rather than leaving two");
  assert.equal(book.sheets.length, 1, "and one sheet, not two");
});

test("the other side can read back exactly what was handed over" , async () => {
  memory.clear(); memory.add(skill);
  const { excel } = fakeExcel();
  await handOff("bill-the-job", { excel });

  const got = await readHandoff({ excel });
  assert.equal(got.skill, "bill-the-job");
  assert.equal(got.version, "3");
  assert.equal(got.content_hash, "a".repeat(64));
  assert.ok(got.directions.includes("Hold retainage"));
  assert.ok(got.handed_at);
});

test("reading when nothing was handed over returns nothing, not a crash", async () => {
  const { excel } = fakeExcel();
  assert.equal(await readHandoff({ excel }), null);
});

test("outside Excel it still builds the bundle and writes nothing", async () => {
  memory.clear(); memory.add(skill);
  const out = await handOff("bill-the-job", { excel: null });
  assert.deepEqual([out.xml, out.sheet], [false, false], "Word and PowerPoint have no sheet to write to");
  assert.equal(out.bundle.skill, "bill-the-job");
});

test("handing over something we do not have says so" , async () => {
  memory.clear();
  await assert.rejects(() => handOff("missing", { excel: fakeExcel().excel }), /not in this add-in's memory/);
});
