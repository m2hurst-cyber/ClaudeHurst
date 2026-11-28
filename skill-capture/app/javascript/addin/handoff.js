// Handing a skill's directions to whatever else is working in this document.
//
// Two add-ins in one workbook cannot call each other — separate WebViews, separate
// origins, no handles. The document is the only channel, and which part of the document
// depends on who is listening:
//
//   a cooperating add-in  → a custom XML part under our namespace. Structured, invisible,
//                           travels with the file. They have to know to look.
//   an AI reading the book → a worksheet. It will never learn our namespace, but whatever
//                           is in the sheet is in its context.
//
// Both are written, because we rarely know which is on the other side.
import { memory } from "addin/memory";

export const NAMESPACE = "urn:skill-capture:handoff";
export const SHEET = "Skill Capture";

// What gets handed over. The content hash travels with it so that whatever acts on these
// directions can say which version of which skill it followed.
export function bundle(name) {
  const m = memory.get(name);
  if (!m) return null;
  return {
    skill: m.name,
    title: m.title || m.name,
    version: m.version || null,
    content_hash: m.content_hash || null,
    handed_at: new Date().toISOString(),
    directions: memory.asContext(name)
  };
}

export function toXml(b) {
  const esc = (v) => String(v ?? "").replace(/[<>&]/g, (c) => ({ "<": "&lt;", ">": "&gt;", "&": "&amp;" }[c]));
  return `<handoff xmlns="${NAMESPACE}">` +
    `<skill>${esc(b.skill)}</skill><title>${esc(b.title)}</title>` +
    `<version>${esc(b.version)}</version><contentHash>${esc(b.content_hash)}</contentHash>` +
    `<handedAt>${esc(b.handed_at)}</handedAt>` +
    `<directions>${esc(b.directions)}</directions></handoff>`;
}

// The sheet an AI will actually read. Visible on purpose: hidden is tidier and may be
// skipped, and being read is the whole point. Row one says it is safe to delete.
export function rows(b) {
  const header = [
    ["Directions for an AI assistant — written by Skill Capture. Safe to delete."],
    [`${b.title}${b.version ? ` · v${b.version}` : ""}${b.content_hash ? ` · ${String(b.content_hash).slice(0, 12)}` : ""}`],
    [""]
  ];
  const body = String(b.directions || "").split("\n").map((line) => [line]);
  return header.concat(body.length ? body : [[""]]);
}

// Excel. Word and PowerPoint have no sheet, so they get the XML part alone.
export async function handOff(name, { excel = (typeof Excel !== "undefined" ? Excel : null) } = {}) {
  const b = bundle(name);
  if (!b) throw new Error(`${name} is not in this add-in's memory`);
  if (!excel) return { bundle: b, xml: false, sheet: false };

  let wroteXml = false;
  let wroteSheet = false;

  await excel.run(async (context) => {
    // One handoff at a time: replace ours rather than pile them up.
    const parts = context.workbook.customXmlParts.getByNamespace(NAMESPACE);
    parts.load("items/id");
    await context.sync();
    parts.items.forEach((part) => part.delete());
    context.workbook.customXmlParts.add(toXml(b));
    wroteXml = true;

    const sheets = context.workbook.worksheets;
    sheets.load("items/name");
    await context.sync();

    const existing = sheets.items.find((s) => s.name === SHEET);
    if (existing) existing.delete();
    const sheet = sheets.add(SHEET);

    const data = rows(b);
    const range = sheet.getRangeByIndexes(0, 0, data.length, 1);
    range.values = data;
    range.format.wrapText = false;
    sheet.getRange("A1").format.font.bold = true;
    sheet.getRange("A:A").format.columnWidth = 520;
    wroteSheet = true;

    await context.sync();
  });

  return { bundle: b, xml: wroteXml, sheet: wroteSheet };
}

// What another add-in would call to collect what we left. Here so the shape is written
// down somewhere a partner can read, and so our own tests exercise both ends.
export async function readHandoff({ excel = (typeof Excel !== "undefined" ? Excel : null) } = {}) {
  if (!excel) return null;
  let xml = null;
  await excel.run(async (context) => {
    const parts = context.workbook.customXmlParts.getByNamespace(NAMESPACE);
    parts.load("items/id");
    await context.sync();
    if (!parts.items.length) return;
    const body = parts.items[parts.items.length - 1].getXml();
    await context.sync();
    xml = body.value;
  });
  if (!xml) return null;
  const field = (tag) => (xml.match(new RegExp(`<${tag}>([\\s\\S]*?)</${tag}>`)) || [])[1] || null;
  const unesc = (v) => (v == null ? null : v.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&"));
  return {
    skill: unesc(field("skill")), title: unesc(field("title")),
    version: unesc(field("version")), content_hash: unesc(field("contentHash")),
    handed_at: unesc(field("handedAt")), directions: unesc(field("directions"))
  };
}

if (typeof window !== "undefined") window.SkillCaptureHandoff = { handOff, readHandoff, NAMESPACE, SHEET };
