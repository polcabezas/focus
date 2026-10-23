const api = globalThis.browser ?? globalThis.chrome;
const WS_URL = "ws://127.0.0.1:47823";
const EMPTY_RULES = { blockedDomains: [], until: null };

let rules = EMPTY_RULES;
let ws = null;
let heartbeat = null;
let storedJSON = "";

const isWeb = (url) => /^https?:\/\//i.test(url || "");
const hostOf = (url) => { try { return new URL(url).hostname; } catch { return ""; } };
const matches = (host, domains) => domains.some((d) => host === d || host.endsWith("." + d));
const blockPageURL = (url) => api.runtime.getURL("blocked.html") + "?u=" + encodeURIComponent(url);

function send(msg) {
  if (!ws || ws.readyState !== WebSocket.OPEN) return false;
  ws.send(JSON.stringify(msg));
  return true;
}

function setRules(next) {
  const json = JSON.stringify(next);
  if (json === storedJSON) return;
  storedJSON = json;
  rules = next;
  console.log("rules applied", next.until, next.blockedDomains.length);
  api.storage.local.set({ rules }).catch(() => {});
  scanTabs();
}

// Rules stay in force until `until` even if the socket drops or the background was asleep.
function active() {
  if (!rules.until || Date.parse(rules.until) <= Date.now()) setRules(EMPTY_RULES);
  return rules;
}

function isBlocked(url) {
  return isWeb(url) && matches(hostOf(url), active().blockedDomains);
}

function redirect(tabId, url) {
  api.tabs.update(tabId, { url: blockPageURL(url) }).catch(() => {});
}

function scanTabs() {
  if (!active().blockedDomains.length) return;
  api.tabs.query({}).then((tabs) => {
    for (const tab of tabs) if (isBlocked(tab.url)) redirect(tab.id, tab.url);
  }).catch(() => {});
}

function connect() {
  if (ws && ws.readyState <= WebSocket.OPEN) return;
  ws = new WebSocket(WS_URL);
  ws.onopen = () => {
    console.log("bridge open");
    send({ type: "hello", ua: navigator.userAgent });
    clearInterval(heartbeat);
    heartbeat = setInterval(() => send({ type: "heartbeat" }), 10000);
  };
  ws.onmessage = (event) => {
    let msg;
    try { msg = JSON.parse(event.data); } catch { return; }
    if (msg.type !== "rules") return;
    setRules({
      blockedDomains: msg.blockedDomains ?? [],
      until: msg.until ?? null,
    });
  };
  ws.onclose = (event) => {
    console.log("bridge closed, code", event.code);
    clearInterval(heartbeat);
    ws = null;
    setTimeout(connect, 2000);
  };
  ws.onerror = () => {};
}

// A navigation can wake a sleeping background before its stored rules are loaded, so events wait for this.
const started = api.storage.local.get("rules")
  .then((stored) => {
    if (stored.rules) {
      rules = { ...EMPTY_RULES, ...stored.rules };
      storedJSON = JSON.stringify(rules);
    }
    scanTabs();
  })
  .catch(() => {})
  .then(connect);

api.webNavigation.onBeforeNavigate.addListener((details) => {
  if (details.frameId !== 0) return;
  started.then(() => { if (isBlocked(details.url)) redirect(details.tabId, details.url); });
});

api.tabs.onUpdated.addListener((tabId, changeInfo) => {
  if (!changeInfo.url) return;
  started.then(() => { if (isBlocked(changeInfo.url)) redirect(tabId, changeInfo.url); });
});

api.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg?.type === "ping") {
    started.then(connect);
    sendResponse({ ok: true });
  } else if (msg?.type === "getRules") {
    sendResponse({ ...active(), connected: !!ws && ws.readyState === WebSocket.OPEN });
  } else if (msg?.type === "backToWork") {
    const tab = sender.tab;
    if (tab) {
      try { api.tabs.remove(tab.id).catch(() => {}); } catch {}
    }
    sendResponse({ tab: !!tab });
  }
});
