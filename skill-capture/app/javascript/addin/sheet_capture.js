// Turns a used range's formulas and values into what Skill Capture observes: each cell's formula, or its
// text label, or just the fact that a number is there. Numbers are never sent.
import { colLetter } from "addin/worksheet_builder";

export const MAX_CELLS = 5000;

// "Sheet1!B2:F17" or "B2:F17" → { row: 2, col: 1 } (1-based row, 0-based column)
export function rangeOrigin(address) {
  const m = /([A-Z]{1,3})(\d+)(?::|$)/.exec(String(address || "").split("!").pop().replace(/\$/g, ""));
  if (!m) return { row: 1, col: 0 };
  const col = m[1].split("").reduce((n, ch) => n * 26 + ch.charCodeAt(0) - 64, 0) - 1;
  return { row: Number(m[2]), col };
}

export function observeCells(formulas, values, address) {
  const { row, col } = rangeOrigin(address);
  const cells = [];
  let truncated = false;
  (formulas || []).forEach((r, i) => (r || []).forEach((f, j) => {
    if (cells.length >= MAX_CELLS) { truncated = true; return; }
    const a = `${colLetter(col + j)}${row + i}`;
    const v = values?.[i]?.[j];
    if (typeof f === "string" && f.startsWith("=")) cells.push({ a, f });
    else if (typeof v === "string" && v.trim() !== "") cells.push({ a, t: v.trim().slice(0, 120) });
    else if (typeof v === "number" || typeof v === "boolean") cells.push({ a, n: true });
  }));
  return { cells, truncated };
}
