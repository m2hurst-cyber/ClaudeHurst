// The add-in's own ribbon tab ("Skill Capture") calls these functions in the shared runtime
// (manifest: ExecuteFunction actions). Each one must call event.completed(), whatever happens,
// or Office keeps the button busy.
export const RIBBON_ACTIONS = ["focusSearch", "showMemory", "showRecord", "showReview", "captureSheet", "startRecording", "toggleCapture", "openMap", "openLibrary", "openReturns", "openConsole"];

export function registerRibbon(office, handlers) {
  const associate = office?.actions?.associate;
  if (!associate) return [];
  return RIBBON_ACTIONS.filter((name) => handlers[name]).map((name) => {
    office.actions.associate(name, async (event) => {
      try { await handlers[name](event); }
      catch (e) { console.error(`Skill Capture: ${name} failed`, e); }
      finally { event?.completed?.(); }
    });
    return name;
  });
}

// Opens the side pane from a ribbon button (shared runtime only; harmless elsewhere).
export async function showPane(office) {
  try { await office?.addin?.showAsTaskpane?.(); } catch { /* older clients: the pane button still works */ }
}
