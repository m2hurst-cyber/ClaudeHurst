// Minimal browser / Office add-in collector for Skill Capture.
// Buffers events and sends them in batches to POST /api/v1/events.
//
//   const capture = createCollector({ endpoint: "https://capture.example.org", token: "sc_..." });
//   capture.track("excel.run_macro:month_end", { label: "Run the month-end macro", domain: "finance",
//                                                 actor: { id: pseudonymousUserId } });
//
// Send structure only: what kind of step happened, never document contents,
// cell values, message text or email addresses. The server drops anything
// outside its allowlist anyway.
export function createCollector({ endpoint, token, flushEvery = 10_000, maxBatch = 100 }) {
  const session = crypto.randomUUID();
  let queue = [];

  async function flush() {
    if (queue.length === 0) return;
    const batch = queue.splice(0, maxBatch);
    try {
      const res = await fetch(`${endpoint}/api/v1/events`, {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
        body: JSON.stringify({ events: batch }),
        keepalive: true,
      });
      if (res.status >= 500) queue = batch.concat(queue); // retry later
    } catch {
      queue = batch.concat(queue);
    }
  }

  setInterval(flush, flushEvery);
  addEventListener?.("pagehide", flush);

  return {
    track(action, { label, domain, actor, resource, context } = {}) {
      queue.push({ action, label, domain, actor, resource, context, session, occurred_at: new Date().toISOString() });
      if (queue.length >= maxBatch) flush();
    },
    flush,
  };
}
