// Pings the background while a tab is visible, so WebKit doesn't suspend it (and drop the bridge) during browsing.
const api = globalThis.browser ?? globalThis.chrome;

function ping() {
  try {
    Promise.resolve(api.runtime.sendMessage({ type: "ping" })).catch(() => {});
  } catch {}
}

ping();
setInterval(() => {
  try {
    if (document.visibilityState === "visible") ping();
  } catch {}
}, 20000);
