const api = globalThis.browser ?? globalThis.chrome ?? null;
const $ = (id) => document.getElementById(id);
const params = new URLSearchParams(location.search);
const original = params.get("u") || "";
// Mock mode: opened as a plain file (no extension APIs) or with ?preview=1. Nothing reaches the background.
const mock = !api || params.get("preview") === "1";
const host = (() => { try { return new URL(original).hostname; } catch { return ""; } })();

let until = null;
let rules = null;

const isBlocked = (r) => !!host && (r.blockedDomains || []).some((d) => host === d || host.endsWith("." + d));

const pad = (n) => String(n).padStart(2, "0");
function format(ms) {
  const s = Math.max(0, Math.ceil(ms / 1000));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  return h ? `${h}:${pad(m)}:${pad(s % 60)}` : `${pad(m)}:${pad(s % 60)}`;
}

function clock(iso) {
  const d = new Date(iso);
  return isNaN(d) ? "" : `${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function mockRules() {
  return {
    blockedDomains: ["youtube.com"],
    until: new Date(Date.now() + 23 * 60 * 1000).toISOString(),
  };
}

// Every extension call goes through here. Mock mode answers locally; failures reject and callers catch them.
function send(msg) {
  if (mock) {
    if (msg.type === "getRules") return Promise.resolve(mockRules());
    return Promise.resolve({ tab: false });
  }
  try {
    return Promise.resolve(api.runtime.sendMessage(msg));
  } catch (e) {
    return Promise.reject(e);
  }
}

function tick() {
  if (!until) return;
  const left = Date.parse(until) - Date.now();
  $("countdown").textContent = format(left);
  if (left <= 0 && rules) send({ type: "getRules" }).then(onRules).catch(() => {});
}

function render(r) {
  rules = r;
  if (!mock && !isBlocked(r) && /^https?:\/\//i.test(original)) {
    location.replace(original);
    return;
  }
  until = r.until || null;
  const time = until ? clock(until) : "";
  $("line").textContent = `${host || "this site"} is off the table${time ? ` until ${time}` : " for now"}.`;
  tick();
}

function onRules(r) {
  if (r) render(r);
}

$("back").addEventListener("click", async () => {
  let closed = false;
  try {
    closed = !!(await send({ type: "backToWork" }))?.tab;
  } catch {}
  if (!closed) window.close();
});

if (!mock) {
  try {
    api.storage.onChanged.addListener((changes, area) => {
      if (area === "local" && changes.rules && changes.rules.newValue) render(changes.rules.newValue);
    });
  } catch {}
}

send({ type: "getRules" }).then(onRules).catch(() => {});
setInterval(tick, 1000);
