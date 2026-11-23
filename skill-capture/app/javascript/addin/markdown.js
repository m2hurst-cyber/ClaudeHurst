// Tiny, safe Markdown → HTML for skill bodies (headings, lists, paragraphs, quotes, code, bold, italics).
const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
const inline = (s) => esc(s)
  .replace(/`([^`]+)`/g, '<code class="text-xs bg-slate-100 rounded px-1">$1</code>')
  .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
  .replace(/(^|[\s(])_([^_]+)_(?=[\s).,;:!?]|$)/g, "$1<em>$2</em>");

export function renderMarkdown(md) {
  const out = [];
  let list = null;
  const close = () => { if (list) { out.push(`</${list}>`); list = null; } };
  for (const raw of String(md || "").split("\n")) {
    const line = raw.replace(/\s+$/, "");
    let m;
    if ((m = line.match(/^(#{1,4})\s+(.*)/))) { close(); const lvl = Math.min(m[1].length + 1, 4); out.push(`<h${lvl} class="font-semibold mt-3 mb-1">${inline(m[2])}</h${lvl}>`); }
    else if ((m = line.match(/^\s*\d+\.\s+(.*)/))) { if (list !== "ol") { close(); list = "ol"; out.push('<ol class="list-decimal ml-5 space-y-1">'); } out.push(`<li>${inline(m[1])}</li>`); }
    else if ((m = line.match(/^\s*[-*]\s+(.*)/))) { if (list !== "ul") { close(); list = "ul"; out.push('<ul class="list-disc ml-5 space-y-1">'); } out.push(`<li>${inline(m[1])}</li>`); }
    else if (/^\s{2,}\S/.test(line) && list) { out[out.length - 1] = out[out.length - 1].replace(/<\/li>$/, ` <span class="block text-slate-500">${inline(line.trim())}</span></li>`); }
    else if ((m = line.match(/^>\s?(.*)/))) { close(); out.push(`<blockquote class="border-l-2 pl-2 text-slate-500">${inline(m[1])}</blockquote>`); }
    else if (line.trim() === "") { close(); }
    else { close(); out.push(`<p class="my-1">${inline(line)}</p>`); }
  }
  close();
  return out.join("\n");
}

export function toPlainSteps(skill) {
  return `${skill.title}\n\n${String(skill.body || "").replace(/^#+\s*/gm, "").replace(/[`*_]/g, "")}`.trim();
}
