// The steps the add-in can observe through Office.js, and how they read to people.
// Keys are structural on purpose: no file names, sheet names, cell values or text.
export const VOCABULARY = {
  "excel.document.opened": "Open the workbook",
  "excel.worksheet.added": "Add a worksheet",
  "excel.worksheet.deleted": "Delete a worksheet",
  "excel.worksheet.switched": "Switch to another worksheet",
  "excel.cells.edited": "Enter or edit cell values",
  "excel.formula.changed": "Enter or change a formula",
  "excel.format.changed": "Format cells",
  "excel.rows.inserted": "Insert rows",
  "excel.rows.deleted": "Delete rows",
  "excel.columns.inserted": "Insert columns",
  "excel.columns.deleted": "Delete columns",
  "excel.cells.inserted": "Insert cells",
  "excel.cells.deleted": "Delete cells",
  "excel.data.sorted": "Sort data",
  "excel.rows.hidden": "Hide or unhide rows",
  "excel.table.added": "Create a table",
  "excel.table.deleted": "Delete a table",
  "word.document.opened": "Open the document",
  "word.paragraph.added": "Add paragraphs",
  "word.paragraph.changed": "Edit text",
  "word.paragraph.deleted": "Delete paragraphs",
  "word.contentcontrol.added": "Insert a form field (content control)",
  "powerpoint.document.opened": "Open the presentation",
  "powerpoint.slide.added": "Add a slide",
  "powerpoint.slide.deleted": "Delete a slide",
};

// Excel.WorksheetChangedEventArgs.changeType → step key
export const EXCEL_CHANGE_TYPES = {
  RangeEdited: "excel.cells.edited",
  RowInserted: "excel.rows.inserted",
  RowDeleted: "excel.rows.deleted",
  ColumnInserted: "excel.columns.inserted",
  ColumnDeleted: "excel.columns.deleted",
  CellInserted: "excel.cells.inserted",
  CellDeleted: "excel.cells.deleted",
};

// One user edit can fire several events (an edited formula fires both "changed" and
// "formula changed"). Within this window the more specific step replaces the generic one.
export const SUPERSEDES = { "excel.formula.changed": ["excel.cells.edited"] };
export const SUPERSEDE_WINDOW_MS = 1500;

export const HOST_PREFIX = { Excel: "excel", Word: "word", PowerPoint: "powerpoint" };

export function slug(text) {
  return String(text).toLowerCase().normalize("NFKD").replace(/[^\w\s-]/g, "")
    .trim().replace(/[\s_]+/g, "-").replace(/-+/g, "-").slice(0, 60).replace(/-+$/, "") || "step";
}

// A step the person types while recording (e.g. "Check totals match the bank statement").
export function manualStep(host, text) {
  const label = String(text).trim().replace(/\s+/g, " ").slice(0, 200);
  return { action: `${HOST_PREFIX[host] || "office"}.step:${slug(label)}`, label };
}
