import { test } from "node:test";
import assert from "node:assert/strict";
import { plan, apply, colLetter } from "addin/worksheet_builder";

const commands = {
  revenue: { syntax: '=BQL({security},"sales_rev_turn(fpt={fpt}, fpo={fpo})")', defaults: { fpt: "A", fpo: 0 }, status: "verified" },
  net_income: { syntax: '=BQL({security},"net_income(fpt={fpt}, fpo={fpo})")', defaults: { fpt: "A", fpo: 0 } },
  fcf_est: { syntax: '=BQL({security},"cf_free_cash_flow(fpt=A, fpo={fpo}, ae=E)")', defaults: { fpo: 1 } },
  net_debt: { syntax: '=BQL({security},"net_debt(fpt=A, fpo=0)")' },
  shares_out: { syntax: '=BQL({security},"eqy_sh_out")' },
  pe_ratio: { syntax: '=BQL({security},"pe_ratio")', status: "verified" },
  esg_score: { syntax: '=FDS({security},"{esg_code}")', defaults: { esg_code: "" } },
};
const cell = (p, a) => p.cells.find((c) => c.address === a);
const fin = { kind: "table", sheet: "Financials", title: "Financials", inputs: [{ key: "security", label: "Security", default: "AAPL US Equity" }],
  columns: [{ label: "FY-1", params: { fpo: -1 } }, { label: "FY0", params: { fpo: 0 } }],
  rows: [{ key: "revenue", label: "Revenue", command: "revenue" }, { key: "net_income", label: "Net income", command: "net_income" },
         { key: "margin", label: "Net margin", formula: "={row:net_income}/{row:revenue}", format: "0.0%" }],
  summary: [{ key: "total", label: "Two-year revenue", formula: "={row_sum:revenue}" }] };

test("column letters", () => { assert.deepEqual([0, 1, 25, 26, 27, 701].map(colLetter), ["A", "B", "Z", "AA", "AB", "ZZ"]); });

test("a table: inputs as cells, provider formulas per period, computed rows in the same column, summary cells", () => {
  const p = plan(fin, { commands, inputs: { security: "MSFT US Equity" } });
  assert.deepEqual(p.warnings, []);
  assert.equal(cell(p, "B3").value, "MSFT US Equity");
  assert.deepEqual([cell(p, "B5").value, cell(p, "C5").value], ["FY-1", "FY0"]);
  assert.equal(cell(p, "B6").formula, '=BQL($B$3,"sales_rev_turn(fpt=A, fpo=-1)")');
  assert.equal(cell(p, "C7").formula, '=BQL($B$3,"net_income(fpt=A, fpo=0)")');
  assert.equal(cell(p, "C8").formula, "=C7/C6");
  assert.equal(cell(p, "B10").formula, "=SUM(B6:C6)");
  assert.deepEqual(p.unverified, ["net_income"], "verified commands aren't flagged");
});

test("a table can read another sheet column by column, with the previous column for growth", () => {
  const ratios = { kind: "table", sheet: "Ratios", source: "fin", columns: fin.columns,
    rows: [{ key: "growth", label: "Growth", formula: '=IFERROR({src_row:revenue}/{src_prev:revenue}-1,"")' }] };
  const p = plan(ratios, { commands, sources: { fin } });
  assert.equal(cell(p, "C5").formula, `=IFERROR('Financials'!C6/'Financials'!B6-1,"")`);
});

test("a grid: one row per security, the security cell feeds each formula, quoted inputs are spliced in, median and mean", () => {
  const g = { kind: "grid", sheet: "ESG", inputs: [{ key: "peers", type: "list", label: "Security", default: "A-US\nB-US" }, { key: "esg_code", label: "ESG code", default: "TV_SCORE" }],
    columns: [{ key: "esg_score", label: "ESG", command: "esg_score" }] };
  const p = plan(g, { commands });
  assert.equal(cell(p, "B3").value, "TV_SCORE");
  assert.equal(cell(p, "A6").value, "A-US");
  assert.equal(cell(p, "B6").formula, '=FDS($A6,""&$B$3&"")');
  assert.equal(cell(p, "B9").formula, '=IFERROR(MEDIAN(B6:B7),"")');
  const missing = plan({ ...g, inputs: [g.inputs[0]] }, { commands });
  assert.match(missing.warnings[0], /set “esg_code”/);
});

test("a DCF and its sensitivity grid: discounting, terminal value, and a WACC x growth grid that reads the DCF sheet", () => {
  const dcf = { kind: "table", sheet: "DCF", inputs: [{ key: "security", default: "X" }, { key: "wacc", default: 0.09 }, { key: "g", default: 0.02 }],
    columns: [1, 2, 3].map((n) => ({ label: `FY+${n}`, params: { fpo: n, n } })),
    rows: [{ key: "fcf", label: "FCF", command: "fcf_est" }, { key: "df", label: "DF", formula: "=1/(1+{input:wacc})^{col:n}" }],
    summary: [{ key: "tv", label: "TV", formula: "={row_last:fcf}*(1+{input:g})/({input:wacc}-{input:g})" },
              { key: "net_debt", label: "Net debt", command: "net_debt" }, { key: "shares", label: "Shares", command: "shares_out" }] };
  const p = plan(dcf, { commands });
  assert.equal(cell(p, "D9").formula, "=1/(1+$B$4)^3");
  assert.equal(cell(p, "B11").formula, "=D8*(1+$B$5)/($B$4-$B$5)");
  const sens = { kind: "sensitivity", sheet: "Sens", source: "dcf", row_param: { label: "WACC", values: [0.08, 0.1] }, col_param: { label: "g", values: [0.01, 0.02] },
    formula: "=(NPV({row},{src_row_range:fcf})+{src_row_last:fcf}*(1+{col})/({row}-{col})/(1+{row})^{src_count}-{src_cell:net_debt})/{src_cell:shares}" };
  const s = plan(sens, { commands, sources: { dcf } });
  assert.deepEqual(s.warnings, []);
  assert.equal(cell(s, "C7").formula, "=(NPV($A7,'DCF'!B8:D8)+'DCF'!$D$8*(1+C$5)/($A7-C$5)/(1+$A7)^3-'DCF'!$B$12)/'DCF'!$B$13");
  assert.match(plan(sens, { commands }).warnings[0], /Build “dcf” first/);
});

test("a chart: series from a table's rows or a grid's columns, placed beside the source", () => {
  const ch = plan({ kind: "chart", source: "fin", chart: "Line", series: ["revenue", "margin"] }, { commands, sources: { fin } });
  assert.equal(ch.sheet, "Financials");
  assert.deepEqual(ch.charts[0].series.map((x) => [x.nameText, x.values, x.categories]), [["Revenue", "B6:C6", "B5:C5"], ["Net margin", "B8:C8", "B5:C5"]]);
  assert.equal(ch.charts[0].at, "E3");
  const grid = { kind: "grid", sheet: "Comps", inputs: [{ key: "peers", type: "list", default: "A\nB\nC" }], columns: [{ key: "pe_ratio", label: "P/E", command: "pe_ratio" }] };
  const gc = plan({ kind: "chart", source: "grid", series: ["pe_ratio"] }, { commands, sources: { grid } });
  assert.deepEqual(gc.charts[0].series[0], { nameText: "P/E", values: "B5:B7", categories: "A5:A7" });
});

test("apply writes values, formulas and formats, replacing an existing sheet's contents", async () => {
  const writes = [];
  const range = (a) => ({ set formulas(v) { writes.push([a, "f", v[0][0]]); }, set values(v) { writes.push([a, "v", v[0][0]]); },
    set numberFormat(v) { writes.push([a, "n", v[0][0]]); }, format: { font: {}, fill: {}, set columnWidth(w) {} }, clear() { writes.push([a, "clear"]); } });
  const ws = { getRange: (a) => range(a ?? "*"), charts: { add() { throw new Error("no charts in a table"); } }, activate() {} };
  const ctx = { workbook: { worksheets: { getItemOrNullObject: () => ({ ...ws, isNullObject: false }), add: () => ws, getItem: () => ws } }, sync: async () => {} };
  const out = await apply(plan(fin, { commands }), { run: (fn) => fn(ctx) });
  assert.equal(out.sheet, "Financials");
  assert.deepEqual(writes[0], ["*", "clear"]);
  assert.ok(writes.some((w) => w[0] === "C8" && w[1] === "f" && w[2] === "=C7/C6"));
  assert.ok(writes.some((w) => w[0] === "B8" && w[1] === "n" && w[2] === "0.0%"));
});

test("a chart over a grid uses the inputs the grid was last built with, so its ranges match the real sheet", () => {
  const grid = { kind: "grid", sheet: "Comps", inputs: [{ key: "peers", type: "list", default: "A\nB" }], columns: [{ key: "pe_ratio", label: "P/E", command: "pe_ratio" }] };
  const sources = { grid: { ...grid, __inputs: { peers: "A\nB\nC\nD" } } };
  const gc = plan({ kind: "chart", source: "grid", series: ["pe_ratio"] }, { commands, sources });
  assert.equal(gc.charts[0].series[0].values, "B5:B8");
});
