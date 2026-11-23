// Layered left-to-right layout for the route map. Pure functions, no DOM.
//
// Each connected group of skills (a "journey network") is laid out on its own:
// a skill's column is the longest chain of roads leading to it (cycles broken),
// rows are ordered to reduce crossings (barycenter sweeps). Networks are stacked
// top to bottom, biggest first. Skills with no roads at all go in a final grid.

export const DEFAULTS = { colWidth: 270, rowHeight: 96, segment: 170, padX: 40, padY: 56, networkGap: 70, gridCols: 4 };

export function layout(nodes, edges, opts = {}) {
  const o = { ...DEFAULTS, ...opts };
  const ids = new Set(nodes.map((n) => n.id));
  const es = edges.filter((e) => ids.has(e.from) && ids.has(e.to) && e.from !== e.to);
  const out = new Map(nodes.map((n) => [n.id, []]));
  const inc = new Map(nodes.map((n) => [n.id, []]));
  // Branches don't move a skill along the road: a variant runs parallel to its parent,
  // so only "next" roads decide columns. Branches still keep the networks together.
  const roads = es.filter((e) => e.kind !== "branch");
  roads.forEach((e) => { out.get(e.from).push(e.to); inc.get(e.to).push(e.from); });
  const near = new Map(nodes.map((n) => [n.id, []]));
  es.forEach((e) => { near.get(e.from).push(e.to); near.get(e.to).push(e.from); });

  const networks = components(nodes, es).sort((a, b) => b.length - a.length || a[0].localeCompare(b[0]));
  const positions = new Map();
  let y = o.padY;
  const loose = [];
  const byId = new Map(nodes.map((n) => [n.id, n]));

  for (const net of networks) {
    if (net.length === 1 && !near.get(net[0]).length) { loose.push(net[0]); continue; }
    const set = new Set(net);
    const back = backEdges(net, out, set);
    const forward = (a) => out.get(a).filter((b) => set.has(b) && !back.has(`${a}>${b}`));
    const col = longestPathColumns(net, forward, set);
    const columns = [];
    net.forEach((id) => { (columns[col.get(id)] ||= []).push(id); });
    columns.forEach((c) => c.sort((a, b) => sortKey(byId.get(a)).localeCompare(sortKey(byId.get(b)))));
    orderRows(columns.filter(Boolean), near, near);
    const rows = Math.max(...columns.filter(Boolean).map((c) => c.length));
    columns.forEach((c, ci) => c && c.forEach((id, ri) => {
      const offset = (rows - c.length) * o.rowHeight / 2; // centre short columns
      positions.set(id, { x: o.padX + ci * o.colWidth, y: y + offset + ri * o.rowHeight, network: networks.indexOf(net) });
    }));
    y += rows * o.rowHeight + o.networkGap;
  }

  if (loose.length) {
    loose.sort((a, b) => sortKey(byId.get(a)).localeCompare(sortKey(byId.get(b))));
    loose.forEach((id, i) => positions.set(id, {
      x: o.padX + (i % o.gridCols) * o.colWidth, y: y + Math.floor(i / o.gridCols) * o.rowHeight, network: -1, loose: true,
    }));
    y += Math.ceil(loose.length / o.gridCols) * o.rowHeight;
  }

  const maxX = Math.max(o.padX, ...[...positions.values()].map((p) => p.x)) + o.segment + o.padX;
  return { positions, width: maxX, height: y + o.padY / 2, looseStartY: loose.length ? positions.get(loose[0]).y : null };
}

function sortKey(n) { return `${n.area || "~"}|${n.kind === "unpaved" ? 1 : 0}|${n.title || n.id}`; }

function components(nodes, edges) {
  const parent = new Map(nodes.map((n) => [n.id, n.id]));
  const find = (x) => { while (parent.get(x) !== x) { parent.set(x, parent.get(parent.get(x))); x = parent.get(x); } return x; };
  edges.forEach((e) => parent.set(find(e.from), find(e.to)));
  const groups = new Map();
  nodes.forEach((n) => { const r = find(n.id); (groups.get(r) || groups.set(r, []).get(r)).push(n.id); });
  return [...groups.values()];
}

// DFS from sources (then any unvisited node); edges to a node on the stack are back edges.
function backEdges(net, out, set) {
  const state = new Map();
  const back = new Set();
  const hasIn = new Set();
  net.forEach((a) => out.get(a).forEach((b) => set.has(b) && hasIn.add(b)));
  const starts = [...net.filter((n) => !hasIn.has(n)).sort(), ...[...net].sort()];
  const visit = (start) => {
    const stack = [[start, 0]];
    state.set(start, 1);
    while (stack.length) {
      const top = stack[stack.length - 1];
      const next = out.get(top[0]).filter((b) => set.has(b));
      if (top[1] < next.length) {
        const b = next[top[1]++];
        if (state.get(b) === 1) back.add(`${top[0]}>${b}`);
        else if (!state.has(b)) { state.set(b, 1); stack.push([b, 0]); }
      } else { state.set(top[0], 2); stack.pop(); }
    }
  };
  starts.forEach((s) => { if (!state.has(s)) visit(s); });
  return back;
}

function longestPathColumns(net, forward, set) {
  const indeg = new Map(net.map((n) => [n, 0]));
  net.forEach((a) => forward(a).forEach((b) => indeg.set(b, indeg.get(b) + 1)));
  const col = new Map(net.map((n) => [n, 0]));
  const queue = net.filter((n) => indeg.get(n) === 0).sort();
  while (queue.length) {
    const a = queue.shift();
    forward(a).forEach((b) => {
      col.set(b, Math.max(col.get(b), col.get(a) + 1));
      indeg.set(b, indeg.get(b) - 1);
      if (indeg.get(b) === 0) queue.push(b);
    });
  }
  return col;
}

function orderRows(columns, out, inc) {
  const index = () => { const m = new Map(); columns.forEach((c) => c.forEach((id, i) => m.set(id, i))); return m; };
  const bary = (id, neighbours, pos) => {
    const ps = neighbours.get(id).filter((n) => pos.has(n)).map((n) => pos.get(n));
    return ps.length ? ps.reduce((a, b) => a + b, 0) / ps.length : pos.get(id);
  };
  for (let sweep = 0; sweep < 4; sweep++) {
    const forwardPass = sweep % 2 === 0;
    const order = forwardPass ? columns.slice(1) : columns.slice(0, -1).reverse();
    order.forEach((c) => {
      const pos = index();
      const keyed = c.map((id) => [bary(id, forwardPass ? inc : out, pos), pos.get(id), id]);
      keyed.sort((a, b) => a[0] - b[0] || a[1] - b[1]);
      c.splice(0, c.length, ...keyed.map((k) => k[2]));
    });
  }
}

// Edge geometry: a smooth road from the end of A's segment to the start of B's.
export function roadPath(a, b, segment) {
  const x1 = a.x + segment, y1 = a.y, x2 = b.x, y2 = b.y;
  if (x2 > x1 + 10) {
    const mx = (x1 + x2) / 2;
    return `M${x1},${y1} C${mx},${y1} ${mx},${y2} ${x2},${y2}`;
  }
  // Backwards (a loop in the network): swing below both segments.
  const dip = Math.max(y1, y2) + 46;
  return `M${x1},${y1} C${x1 + 60},${y1} ${x1 + 60},${dip} ${(x1 + x2) / 2},${dip} S${x2 - 60},${y2} ${x2},${y2}`;
}

// A branch leaves from the middle of the parent road and joins the variant's road
// (which usually runs parallel, in the same column).
export function branchPath(a, b, segment) {
  if (Math.abs(b.x - a.x) < 1) {
    // Parallel variant: a bracket off the left ends, clear of both labels.
    return `M${a.x},${a.y} C${a.x - 34},${a.y} ${b.x - 34},${b.y} ${b.x},${b.y}`;
  }
  const x1 = a.x + segment / 2, y1 = a.y, x2 = b.x, y2 = b.y;
  return `M${x1},${y1} C${x1},${(y1 + y2) / 2} ${x2},${(y1 + y2) / 2} ${x2},${y2}`;
}

export function branchJunction(a, b, segment) {
  return Math.abs(b.x - a.x) < 1 ? { x: a.x, y: a.y } : { x: a.x + segment / 2, y: a.y };
}

export function trafficWidth(traffic, max) {
  if (!traffic) return 3;
  return 3 + Math.round(9 * Math.sqrt(traffic / Math.max(1, max)));
}
