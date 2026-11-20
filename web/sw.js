const CACHE = 'player-pwa-v2';
const SHELL = [
  new URL('./', self.registration.scope).href,
  new URL('index.html', self.registration.scope).href,
  new URL('manifest.json', self.registration.scope).href,
  new URL('icons/icon.svg', self.registration.scope).href
];

self.addEventListener('install', event => event.waitUntil(
  caches.open(CACHE)
    .then(cache => cache.addAll(SHELL))
    .then(() => self.skipWaiting())
));

self.addEventListener('activate', event => event.waitUntil(
  caches.keys()
    .then(keys => Promise.all(
      keys.filter(key => key.startsWith('player-pwa-') && key !== CACHE)
        .map(key => caches.delete(key))
    ))
    .then(() => self.clients.claim())
));

self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  // Always prefer the newest deployed app. Use the cache only when offline.
  event.respondWith(
    fetch(request, { cache: 'no-store' })
      .then(response => {
        if (response.ok) {
          const copy = response.clone();
          caches.open(CACHE).then(cache => cache.put(request, copy));
        }
        return response;
      })
      .catch(async () => {
        const cached = await caches.match(request);
        if (cached) return cached;
        if (request.mode === 'navigate') {
          return (await caches.match(SHELL[1])) || (await caches.match(SHELL[0]));
        }
        return Response.error();
      })
  );
});
