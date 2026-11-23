// The add-in's local memory: skills pulled from the library (or sent from the map) so an AI
// working in this Office app can use them without going back to the server. Persisted per
// device; exposed to other add-in code as window.SkillCaptureMemory.
const KEY = "skillcapture.memory";
const MAX = 50;

const read = () => { try { return JSON.parse(localStorage.getItem(KEY) || "[]"); } catch { return []; } };
const write = (items) => { try { localStorage.setItem(KEY, JSON.stringify(items.slice(0, MAX))); } catch { /* storage full or blocked */ } };

export const memory = {
  list: () => read(),
  get: (name) => read().find((m) => m.name === name) || null,
  // Newest first; a newer copy of the same skill replaces the old one.
  add(bundle, from = null) {
    const items = read().filter((m) => m.name !== bundle.name);
    items.unshift({ ...bundle, from, loaded_at: new Date().toISOString() });
    write(items);
    return items.length;
  },
  remove(name) { write(read().filter((m) => m.name !== name)); },
  clear() { write([]); },
  // Plain text an AI can take as context: the skill, then its directions.
  asContext(name) {
    const m = memory.get(name);
    if (!m) return "";
    const body = String(m.skill_md || "").replace(/^---[\s\S]*?---\s*/, "");
    const dirs = (m.directions || []).map((d) => d.markdown).join("\n\n");
    const res = (m.resources || []).map((r) => `- ${r.name} (${r.key}): ${r.url}`).join("\n");
    return [body, dirs, res && `## Resources\n${res}`].filter(Boolean).join("\n\n");
  },
};

if (typeof window !== "undefined") window.SkillCaptureMemory = memory;
