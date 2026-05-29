self.addEventListener("install", () => {
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener("fetch", () => {
  // Runtime Control is a live operator console. Leave requests on the network
  // path so updates and API reads are never served from stale service-worker data.
});
