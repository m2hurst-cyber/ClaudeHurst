const KEY = "skillcapture.token";

const store = {
  get(k) { try { return localStorage.getItem(k); } catch { return null; } },
  set(k, v) { try { v == null ? localStorage.removeItem(k) : localStorage.setItem(k, v); } catch { /* storage blocked */ } },
};

export const settings = store;

export function createApi(base = location.origin) {
  let token = store.get(KEY);

  async function request(method, path, body) {
    const res = await fetch(base + path, {
      method,
      headers: { "Content-Type": "application/json", Accept: "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) },
      body: body ? JSON.stringify(body) : undefined,
    });
    if (res.status === 401) { setToken(null); throw Object.assign(new Error("Not connected"), { status: 401 }); }
    const data = res.status === 204 ? null : await res.json().catch(() => null);
    if (!res.ok) throw Object.assign(new Error(data?.error || `Request failed (${res.status})`), { status: res.status });
    return data;
  }

  function setToken(t) { token = t; store.set(KEY, t); }

  return {
    get connected() { return !!token; },
    setToken,
    me: () => request("GET", "/api/v1/addin/me"),
    disconnect: async () => { try { await request("DELETE", "/api/v1/addin/me"); } finally { setToken(null); } },
    sendEvents: (payload) => request("POST", "/api/v1/addin/events", payload),
    skills: (q = "", domain = "", app = "", level = "") => request("GET", `/api/v1/addin/skills?q=${encodeURIComponent(q)}&domain=${encodeURIComponent(domain)}&app=${encodeURIComponent(app)}&level=${encodeURIComponent(level)}`),
    captureSheet: (p) => request("POST", "/api/v1/addin/worksheet_captures", p),
    transfers: () => request("GET", "/api/v1/addin/transfers"),
    flows: () => request("GET", "/api/v1/addin/flows"),
    flow: (id) => request("GET", `/api/v1/addin/flows/${id}`),
    createFlow: (p) => request("POST", "/api/v1/addin/flows", p),
    updateFlow: (id, p) => request("PATCH", `/api/v1/addin/flows/${id}`, p),
    flowAgents: () => request("GET", "/api/v1/addin/agents"),
    startFlow: (flowId) => request("POST", "/api/v1/addin/flow_runs", { flow_id: flowId }),
    flowRun: (id) => request("GET", `/api/v1/addin/flow_runs/${id}`),
    completeFlowStep: (id, step, p) => request("POST", `/api/v1/addin/flow_runs/${id}/complete?step=${step}`, p),
    reportRun: (name, p) => request("POST", `/api/v1/addin/skills/${encodeURIComponent(name)}/runs`, p),
    coworkers: (q = "") => request("GET", `/api/v1/addin/transfers/coworkers?q=${encodeURIComponent(q)}`),
    sendSkills: (p) => request("POST", "/api/v1/addin/transfers", p),
    acceptTransfer: (id) => request("POST", `/api/v1/addin/transfers/${id}/accept`),
    declineTransfer: (id) => request("POST", `/api/v1/addin/transfers/${id}/decline`),
    areas: () => request("GET", "/api/v1/addin/areas"),
    commands: (host, platform) => request("GET", `/api/v1/addin/commands?host=${encodeURIComponent(host || "")}&platform=${encodeURIComponent(platform || "")}`),
    bundle: (name) => request("GET", `/api/v1/addin/bundles/${encodeURIComponent(name)}`),
    vote: (name, value, comment) => request("PUT", `/api/v1/addin/skills/${encodeURIComponent(name)}/vote`, { value, comment }),
    skill: (name) => request("GET", `/api/v1/addin/skills/${encodeURIComponent(name)}`),
    candidates: () => request("GET", "/api/v1/addin/candidates"),
    candidate: (id) => request("GET", `/api/v1/addin/candidates/${id}`),
    approve: (id) => request("POST", `/api/v1/addin/candidates/${id}/approve`),
    reject: (id, notes) => request("POST", `/api/v1/addin/candidates/${id}/reject`, { notes }),
    submitProcedure: (p) => request("POST", "/api/v1/addin/procedures", p),
    prompts: () => request("GET", "/api/v1/addin/prompts"),
    respondPrompt: (id, choice, title) => request("POST", `/api/v1/addin/prompts/${id}/respond`, { choice, title }),
  };
}
