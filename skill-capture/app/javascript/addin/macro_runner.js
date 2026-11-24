// Runs an approved macro inside the add-in: the reviewed script, against the live Office document,
// with no AI call. Only code a reviewer approved reaches here (MacroReview#runnable_in_addin?), and the
// script must define `async function run(context)` and return a short line saying what it did.
export const MACRO_TIMEOUT_MS = 60_000;

export function compile(code) {
  const definesRun = /(^|[^\w$])(async\s+)?function\s+run\s*\(|(^|[^\w$])(const|let|var)\s+run\s*=\s*(async\s*)?(\(|function)/;
  if (typeof code !== "string" || !definesRun.test(code)) throw new Error("The macro has no run(context) function.");
  // eslint-disable-next-line no-new-func
  return new Function("context", `${code}\nreturn run(context);`);
}

// Returns { note, duration_ms }. Throws with the script's own message if it fails.
export async function runMacro(code, { host, excel = globalThis.Excel } = {}) {
  if (host !== "Excel" || !excel?.run) throw new Error("Add-in macros run in Excel. Copy this one into the app it belongs to.");
  const fn = compile(code);
  const started = Date.now();
  const result = await Promise.race([
    excel.run(async (context) => await fn(context)),
    new Promise((_, reject) => setTimeout(() => reject(new Error("The macro didn't finish within a minute; it was stopped.")), MACRO_TIMEOUT_MS)),
  ]);
  return { note: String(result ?? "Macro finished").slice(0, 300), duration_ms: Date.now() - started };
}
