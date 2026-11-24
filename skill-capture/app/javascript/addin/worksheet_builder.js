// Turns a skill's worksheet blueprint into cells, formulas, formats and charts, then writes them
// into Excel. plan() is pure (unit-tested); apply() is the only part that touches Office.js.
//
// Blueprint kinds (from the skill's source.worksheet):
//   table        inputs, period columns, rows of provider formulas or computed formulas, summary cells
//   grid         one row per security (from a list input) x one column per field, plus median/mean rows
//   sensitivity  a two-way grid (row values x column values) of a formula over another skill's sheet
//   chart        a chart over rows (table) or columns (grid) of another skill's sheet
//
// Formula templates: {param} (row > column > command defaults; an input with that key wins as a cell
// reference), {input:k}, {col:k}, {row:k} (same column), {row_range:k}, {row_sum:k}, {row_last:k},
// {cell:k} (summary), {count} (data columns), and for sensitivity {row} {col} plus {src_row_range:k},
// {src_row_last:k}, {src_cell:k}, {src_input:k}, {src_count} on the source skill's sheet.
// A source blueprint may carry __inputs (what it was last built with) so ranges line up with the real sheet.

export const colLetter = (n) => { let s = ""; for (n += 1; n > 0; n = Math.floor((n - 1) / 26)) s = String.fromCharCode(65 + ((n - 1) % 26)) + s; return s; };
const q = (sheet) => `'${String(sheet).replace(/'/g, "''")}'`;
const TOKEN = /\{([a-z_]+)(?::([A-Za-z0-9_\-]+))?\}/g;

function layoutInputs(bp, startRow, cells, inputs, warnings) {
  const refs = {};
  const blank = new Set();
  let r = startRow;
  for (const inp of bp.inputs || []) {
    if (inp.type === "list") continue;
    const v = inputs[inp.key] ?? inp.default ?? "";
    if (String(v).trim() === "") blank.add(inp.key);
    cells.push({ address: `A${r}`, value: inp.label, bold: true });
    cells.push({ address: `B${r}`, [String(v).startsWith("=") ? "formula" : "value"]: v, format: inp.format, input: true });
    refs[inp.key] = `$B$${r}`;
    r++;
  }
  return { refs, next: r, blank };
}

function render(template, ctx, warnings, where) {
  return String(template).replace(TOKEN, (m, type, key) => {
    const fn = ctx.resolve(type, key);
    if (fn === undefined || fn === null) { warnings.push(`${where}: can't resolve ${m}`); return m; }
    return String(fn);
  });
}

// Inside a quoted string a cell reference has to be spliced in: "…"&$B$4&"…"
const insideQuotes = (template, offset) => (template.slice(0, offset).match(/"/g) || []).length % 2 === 1;

function commandFormula(cmdKey, params, ctx, warnings, where) {
  const cmd = ctx.commands[cmdKey];
  if (!cmd) { warnings.push(`${where}: unknown command ${cmdKey}`); return `="?${cmdKey}"`; }
  if (cmd.status !== "verified") ctx.unverified.add(cmdKey);
  // A parameter can point at another part of the sheet ("{row:squares}", "{input:wage}", "{cell:total}"),
  // so one library command can feed another instead of being rewritten as a bare formula.
  const resolveParam = (v) => (typeof v === "string" && v.includes("{")
    ? v.replace(TOKEN, (m, type, key) => {
        const r = key === undefined ? ctx.inputs[type] : ctx.resolve(type, key);
        if (r === undefined || r === null) { warnings.push(`${where}: can't resolve ${m}`); return m; }
        return String(r);
      })
    : v);
  const all = { ...(cmd.defaults || {}), ...Object.fromEntries(Object.entries(params).map(([k, v]) => [k, resolveParam(v)])) };
  const tpl = String(cmd.syntax);
  return tpl.replace(TOKEN, (m, type, key, offset) => {
    let v;
    if (key === undefined && ctx.inputs[type] !== undefined) {
      if (ctx.blank?.has(type)) warnings.push(`${where}: set “${type}” (an empty input)`);
      v = insideQuotes(tpl, offset) ? `"&${ctx.inputs[type]}&"` : ctx.inputs[type];
    } else if (key === undefined) {
      v = all[type];
      if (v === "" || v === undefined || v === null) warnings.push(`${where}: set “${type}” for ${cmd.name || cmdKey}`);
    } else v = ctx.resolve(type, key);
    if (v === undefined || v === null) { warnings.push(`${where}: can't resolve ${m}`); return m; }
    return String(v);
  });
}

export function plan(bp, { inputs = {}, commands = {}, sources = {} } = {}) {
  const cells = [], charts = [], warnings = [];
  const unverified = new Set();
  const sheet = bp.sheet;
  cells.push({ address: "A1", value: bp.title || sheet, bold: true, size: 14 });
  const layout = { sheet, rows: {}, summary: {}, inputs: {} };
  const kind = bp.kind || "table";

  if (kind === "table") {
    const { refs, next, blank } = layoutInputs(bp, 3, cells, inputs, warnings);
    layout.inputs = refs;
    const cols = bp.columns || [];
    const h = next + 1, first = 1, last = cols.length;
    layout.header = { row: h, first, last };
    cells.push({ address: `A${h}`, value: bp.row_header || "", bold: true });
    cols.forEach((c, i) => cells.push({ address: `${colLetter(first + i)}${h}`, value: c.label, bold: true, align: "right" }));
    (bp.rows || []).forEach((row, i) => { layout.rows[row.key] = { row: h + 1 + i, first, last }; });
    const sumStart = h + (bp.rows || []).length + 2;
    (bp.summary || []).forEach((s, i) => { layout.summary[s.key] = `$B$${sumStart + i}`; });
    const range = (k) => { const L = layout.rows[k]; return L && `${colLetter(L.first)}${L.row}:${colLetter(L.last)}${L.row}`; };
    // A table can read another skill's sheet column by column (for example ratios from the financials).
    const srcBp = bp.source ? sources[bp.source] : null;
    if (bp.source && !srcBp) warnings.push(`Build “${bp.source}” first: this sheet reads it`);
    const srcLayout = srcBp ? plan(srcBp, { commands, inputs: srcBp.__inputs || {}, sources }).layout : null;
    const srcCell = (k, idx) => srcLayout?.rows[k] && `${q(srcLayout.sheet)}!${colLetter(idx)}${srcLayout.rows[k].row}`;
    const base = (col) => ({ resolve: (type, key) => {
      switch (type) {
        case "input": return refs[key];
        case "col": return col?.params?.[key];
        case "row": return layout.rows[key] && col && `${colLetter(col.index)}${layout.rows[key].row}`;
        case "row_range": return range(key);
        case "row_sum": return range(key) && `SUM(${range(key)})`;
        case "row_last": return layout.rows[key] && `${colLetter(last)}${layout.rows[key].row}`;
        case "cell": return layout.summary[key];
        case "count": return cols.length;
        case "src_row": return col && srcCell(key, col.index);
        case "src_prev": return col && srcCell(key, col.index - 1);
        case "src_input": return srcLayout?.inputs[key] && `${q(srcLayout.sheet)}!${srcLayout.inputs[key]}`;
      }
    }, commands, inputs: refs, unverified, blank });
    (bp.rows || []).forEach((row) => {
      const r = layout.rows[row.key].row;
      cells.push({ address: `A${r}`, value: row.label, indent: row.indent });
      cols.forEach((c, i) => {
        const ctx = base({ params: c.params || {}, index: first + i });
        const where = `${row.label} / ${c.label}`;
        const f = row.command ? commandFormula(row.command, { ...(c.params || {}), ...(row.params || {}) }, ctx, warnings, where)
                              : render(row.formula, ctx, warnings, where);
        cells.push({ address: `${colLetter(first + i)}${r}`, formula: f, format: row.format });
      });
    });
    (bp.summary || []).forEach((s, i) => {
      const r = sumStart + i;
      const ctx = base(null);
      const f = s.command ? commandFormula(s.command, s.params || {}, ctx, warnings, s.label) : render(s.formula, ctx, warnings, s.label);
      cells.push({ address: `A${r}`, value: s.label, bold: !!s.bold });
      cells.push({ address: `B${r}`, formula: f, format: s.format, bold: !!s.bold });
    });
    layout.lastRow = sumStart + Math.max((bp.summary || []).length - 1, 0);
    layout.lastCol = last;
  } else if (kind === "grid") {
    const { refs, next, blank } = layoutInputs(bp, 3, cells, inputs, warnings);
    layout.inputs = refs;
    const listInput = (bp.inputs || []).find((i) => i.type === "list");
    const raw = inputs[listInput?.key] ?? listInput?.default ?? "";
    const securities = (Array.isArray(raw) ? raw : String(raw).split(/[\n,;]+/)).map((s) => s.trim()).filter(Boolean);
    if (!securities.length) warnings.push("No securities listed");
    const cols = bp.columns || [];
    const h = next + 1;
    layout.header = { row: h, first: 1, last: cols.length };
    cells.push({ address: `A${h}`, value: listInput?.label || "Security", bold: true });
    cols.forEach((c, i) => { cells.push({ address: `${colLetter(1 + i)}${h}`, value: c.label, bold: true, align: "right" }); layout.rows[c.key] = { col: 1 + i }; });
    securities.forEach((sec, si) => {
      const r = h + 1 + si;
      cells.push({ address: `A${r}`, value: sec });
      cols.forEach((c, i) => {
        const ctx = { resolve: (type, key) => (type === "input" ? refs[key] : undefined), commands, inputs: { ...refs, security: `$A${r}` }, unverified, blank };
        cells.push({ address: `${colLetter(1 + i)}${r}`, formula: commandFormula(c.command, c.params || {}, ctx, warnings, `${sec} / ${c.label}`), format: c.format });
      });
    });
    const firstData = h + 1, lastData = h + securities.length;
    layout.data = { first: firstData, last: lastData };
    (bp.stats || ["median", "mean"]).forEach((stat, k) => {
      const r = lastData + 2 + k;
      cells.push({ address: `A${r}`, value: stat === "median" ? "Median" : "Mean", bold: true });
      cols.forEach((c, i) => {
        const L = colLetter(1 + i);
        cells.push({ address: `${L}${r}`, formula: `=IFERROR(${stat === "median" ? "MEDIAN" : "AVERAGE"}(${L}${firstData}:${L}${lastData}),"")`, format: c.format, bold: true });
      });
    });
    layout.lastRow = lastData + 3;
    layout.lastCol = cols.length;
  } else if (kind === "sensitivity") {
    const src = sources[bp.source];
    if (!src) warnings.push(`Build “${bp.source}” first: this grid reads its sheet`);
    const s = src ? plan(src, { commands, inputs: src.__inputs || {}, sources }).layout : null;
    const ref = (a) => s && `${q(s.sheet)}!${a}`;
    const srcRange = (k) => s?.rows[k] && `${colLetter(s.rows[k].first)}${s.rows[k].row}:${colLetter(s.rows[k].last)}${s.rows[k].row}`;
    const rv = bp.row_param.values, cv = bp.col_param.values;
    cells.push({ address: "A3", value: `Rows: ${bp.row_param.label} · Columns: ${bp.col_param.label}${src ? ` · from ${s.sheet}` : ""}` });
    const h = 5;
    cells.push({ address: `A${h}`, value: `${bp.row_param.label} \\ ${bp.col_param.label}`, bold: true });
    cv.forEach((v, j) => cells.push({ address: `${colLetter(1 + j)}${h}`, value: v, format: bp.col_param.format, bold: true }));
    rv.forEach((v, i) => {
      const r = h + 1 + i;
      cells.push({ address: `A${r}`, value: v, format: bp.row_param.format, bold: true });
      cv.forEach((_, j) => {
        const L = colLetter(1 + j);
        const ctx = { resolve: (type, key) => {
          switch (type) {
            case "row": return key ? undefined : `$A${r}`;
            case "col": return key ? undefined : `${L}$${h}`;
            case "src_row_range": return srcRange(key) && ref(srcRange(key));
            case "src_row_last": return s?.rows[key] && ref(`$${colLetter(s.rows[key].last)}$${s.rows[key].row}`);
            case "src_cell": return s?.summary[key] && ref(s.summary[key]);
            case "src_input": return s?.inputs[key] && ref(s.inputs[key]);
            case "src_count": return s && s.header.last - s.header.first + 1;
          }
        } };
        cells.push({ address: `${L}${r}`, formula: render(bp.formula, ctx, warnings, `${v} / ${cv[j]}`), format: bp.format });
      });
    });
    layout.lastRow = h + rv.length;
    layout.lastCol = cv.length;
  } else if (kind === "chart") {
    const src = sources[bp.source];
    if (!src) warnings.push(`Build “${bp.source}” first: this chart reads its sheet`);
    else {
      const s = plan(src, { commands, inputs: src.__inputs || {}, sources }).layout;
      const series = [];
      if ((src.kind || "table") === "grid") {
        for (const k of bp.series || []) {
          const c = s.rows[k]; if (!c) { warnings.push(`Unknown column ${k}`); continue; }
          const L = colLetter(c.col);
          series.push({ nameText: (src.columns || []).find((x) => x.key === k)?.label || k, values: `${L}${s.data.first}:${L}${s.data.last}`, categories: `A${s.data.first}:A${s.data.last}` });
        }
      } else {
        const hdr = `${colLetter(s.header.first)}${s.header.row}:${colLetter(s.header.last)}${s.header.row}`;
        for (const k of bp.series || []) {
          const R = s.rows[k]; if (!R) { warnings.push(`Unknown row ${k}`); continue; }
          series.push({ nameText: (src.rows || []).find((x) => x.key === k)?.label || k, values: `${colLetter(R.first)}${R.row}:${colLetter(R.last)}${R.row}`, categories: hdr });
        }
      }
      charts.push({ sheet: s.sheet, type: bp.chart || "Line", title: bp.title, series, at: `${colLetter(s.lastCol + 2)}3` });
      layout.sheet = s.sheet;
    }
  }
  return { sheet: kind === "chart" ? layout.sheet : sheet, kind, cells: kind === "chart" ? [] : cells, charts, warnings, unverified: [...unverified], layout };
}

// Writes the plan into the workbook: (re)creates the sheet, writes values and formulas, formats,
// then adds charts. Rebuilding replaces the sheet's contents.
export async function apply(p, ExcelNS) {
  return ExcelNS.run(async (context) => {
    const sheets = context.workbook.worksheets;
    let ws;
    if (p.kind === "chart") {
      ws = sheets.getItem(p.sheet);
    } else {
      const existing = sheets.getItemOrNullObject(p.sheet);
      await context.sync();
      if (existing.isNullObject) ws = sheets.add(p.sheet);
      else { ws = existing; ws.getRange().clear(); }
      for (const c of p.cells) {
        const rg = ws.getRange(c.address);
        if (c.formula !== undefined) rg.formulas = [[c.formula]];
        else rg.values = [[c.value]];
        if (c.format) rg.numberFormat = [[c.format]];
        if (c.bold) rg.format.font.bold = true;
        if (c.size) rg.format.font.size = c.size;
        if (c.input) rg.format.fill.color = "#FFF7E0";
      }
      ws.getRange("A:A").format.columnWidth = 180;
    }
    for (const ch of p.charts) {
      const s = ch.series;
      if (!s.length) continue;
      const chart = ws.charts.add(ch.type, ws.getRange(s[0].values), "Rows");
      chart.title.text = ch.title || "";
      chart.series.getItemAt(0).delete?.();
      for (const one of s) {
        const ser = chart.series.add();
        ser.setValues(ws.getRange(one.values));
        ser.setXAxisValues(ws.getRange(one.categories));
        ser.name = one.nameText || "";
      }
      chart.setPosition(ch.at);
    }
    ws.activate();
    await context.sync();
    return { sheet: p.sheet, cells: p.cells.length, charts: p.charts.length };
  });
}
