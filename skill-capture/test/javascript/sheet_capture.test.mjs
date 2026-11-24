import { test } from "node:test";
import assert from "node:assert/strict";
import { observeCells, rangeOrigin } from "addin/sheet_capture";

test("range origin from an Excel address", () => {
  assert.deepEqual(rangeOrigin("DCF!B2:F17"), { row: 2, col: 1 });
  assert.deepEqual(rangeOrigin("'My sheet'!$AA$10:$AB$12"), { row: 10, col: 26 });
  assert.deepEqual(rangeOrigin("A1"), { row: 1, col: 0 });
});

test("formulas and labels are observed; numbers are only flagged, never sent", () => {
  const formulas = [["Security", "AAPL US Equity"], ["WACC", 0.09], ["Revenue", '=BQL($B$1,"sales_rev_turn")'], ["", ""]];
  const values = [["Security", "AAPL US Equity"], ["WACC", 0.09], ["Revenue", 391035], ["", ""]];
  const { cells, truncated } = observeCells(formulas, values, "Sheet1!A1:B4");
  assert.equal(truncated, false);
  assert.deepEqual(cells, [
    { a: "A1", t: "Security" }, { a: "B1", t: "AAPL US Equity" },
    { a: "A2", t: "WACC" }, { a: "B2", n: true },
    { a: "A3", t: "Revenue" }, { a: "B3", f: '=BQL($B$1,"sales_rev_turn")' },
  ]);
  assert.ok(!JSON.stringify(cells).includes("0.09") && !JSON.stringify(cells).includes("391035"));
});

test("large sheets are capped", () => {
  const big = Array.from({ length: 200 }, () => Array.from({ length: 30 }, () => "=1+1"));
  const { cells, truncated } = observeCells(big, big, "A1");
  assert.equal(cells.length, 5000);
  assert.equal(truncated, true);
});
