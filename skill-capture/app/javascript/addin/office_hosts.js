import { EXCEL_CHANGE_TYPES } from "addin/vocabulary";

// Wires Office.js document events to capture.record(). Every registration checks the
// requirement set first and is isolated, so older clients still get what they support.
// Changes made by co-authors (source === "Remote") are ignored: we capture only what
// this person does.

const local = (args) => !args || args.source !== "Remote";
const supported = (set, version) => {
  try { return Office.context.requirements.isSetSupported(set, version); } catch { return false; }
};

async function excel(record, report) {
  await Excel.run(async (context) => {
    const sheets = context.workbook.worksheets;
    const tables = context.workbook.tables;
    const on = (set, ver, target, name, handler) => {
      const label = `Excel ${name}`;
      if (!supported(set, ver) || !target[name]) return report(label, false);
      try { target[name].add(async (args) => { if (local(args)) handler(args); }); report(label, true); }
      catch { report(label, false); }
    };
    on("ExcelApi", "1.7", sheets, "onAdded", () => record("excel.worksheet.added"));
    on("ExcelApi", "1.7", sheets, "onDeleted", () => record("excel.worksheet.deleted"));
    on("ExcelApi", "1.7", sheets, "onActivated", () => record("excel.worksheet.switched"));
    on("ExcelApi", "1.9", sheets, "onChanged", (a) => { const k = EXCEL_CHANGE_TYPES[a.changeType]; if (k) record(k); });
    on("ExcelApi", "1.9", sheets, "onFormatChanged", () => record("excel.format.changed"));
    on("ExcelApi", "1.10", sheets, "onColumnSorted", () => record("excel.data.sorted"));
    on("ExcelApi", "1.10", sheets, "onRowSorted", () => record("excel.data.sorted"));
    on("ExcelApi", "1.11", sheets, "onRowHiddenChanged", () => record("excel.rows.hidden"));
    on("ExcelApi", "1.13", sheets, "onFormulaChanged", () => record("excel.formula.changed"));
    on("ExcelApi", "1.9", tables, "onAdded", () => record("excel.table.added"));
    on("ExcelApi", "1.9", tables, "onDeleted", () => record("excel.table.deleted"));
    await context.sync();
  });
}

async function word(record, report) {
  await Word.run(async (context) => {
    const doc = context.document;
    const on = (set, ver, name, key) => {
      const label = `Word ${name}`;
      if (!supported(set, ver) || !doc[name]) return report(label, false);
      try { doc[name].add(async (args) => { if (local(args)) record(key); }); report(label, true); }
      catch { report(label, false); }
    };
    on("WordApi", "1.6", "onParagraphAdded", "word.paragraph.added");
    on("WordApi", "1.6", "onParagraphChanged", "word.paragraph.changed");
    on("WordApi", "1.6", "onParagraphDeleted", "word.paragraph.deleted");
    on("WordApi", "1.5", "onContentControlAdded", "word.contentcontrol.added");
    await context.sync();
  });
}

// PowerPoint has no slide-added event; compare the slide count when the selection changes.
async function powerpoint(record, report) {
  if (!supported("PowerPointApi", "1.2")) return report("PowerPoint slide count", false);
  const count = () => PowerPoint.run(async (context) => {
    const c = context.presentation.slides.getCount();
    await context.sync();
    return c.value;
  });
  let slides = await count();
  Office.context.document.addHandlerAsync(Office.EventType.DocumentSelectionChanged, async () => {
    try {
      const n = await count();
      if (n > slides) record("powerpoint.slide.added");
      else if (n < slides) record("powerpoint.slide.deleted");
      slides = n;
    } catch { /* ignore transient errors while the user is editing */ }
  });
  report("PowerPoint slide count", true);
}

const WIRES = { Excel: excel, Word: word, PowerPoint: powerpoint };

export async function wireHost(host, record) {
  const wire = WIRES[host];
  if (!wire) return { supported: false, events: {} };
  const events = {};
  const report = (name, ok) => { events[name] = ok; };
  await wire(record, report);
  record(`${host.toLowerCase()}.document.opened`);
  return { supported: true, events };
}

// Keep capturing when the document opens, even before the pane is shown (shared runtime).
export async function setAutoLoad(on) {
  if (!supported("SharedRuntime", "1.1") || !Office.addin?.setStartupBehavior) return false;
  await Office.addin.setStartupBehavior(on ? Office.StartupBehavior.load : Office.StartupBehavior.none);
  return true;
}

// Put text at the cursor / selected cell / selected shape, in any host.
export function insertText(text) {
  return new Promise((resolve, reject) => {
    Office.context.document.setSelectedDataAsync(text, { coercionType: Office.CoercionType.Text }, (r) =>
      r.status === Office.AsyncResultStatus.Succeeded ? resolve() : reject(new Error(r.error?.message || "Insert failed")));
  });
}

export function openInBrowser(url) {
  try {
    if (supported("OpenBrowserWindowApi", "1.1")) return Office.context.ui.openBrowserWindow(url);
  } catch { /* fall through */ }
  window.open(url, "_blank", "noopener");
}

// Sign-in happens in an Office dialog; the dialog posts back a personal token.
export function connectDialog(url) {
  return new Promise((resolve, reject) => {
    Office.context.ui.displayDialogAsync(url, { height: 60, width: 30 }, (result) => {
      if (result.status !== Office.AsyncResultStatus.Succeeded) return reject(new Error(result.error.message));
      const dialog = result.value;
      dialog.addEventHandler(Office.EventType.DialogMessageReceived, (arg) => {
        dialog.close();
        try { resolve(JSON.parse(arg.message)); } catch (e) { reject(e); }
      });
      dialog.addEventHandler(Office.EventType.DialogEventReceived, () => reject(new Error("Sign-in window closed")));
    });
  });
}
