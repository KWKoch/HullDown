// Broadside test-channel service worker: always fetches the newest files (network first,
// revalidating with the server every time); the saved copy is only used when offline.
const CACHE = 'broadside-net-first';
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => {
	e.waitUntil(caches.keys()
		.then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
		.then(() => self.clients.claim()));
});
self.addEventListener('fetch', (e) => {
	const req = e.request;
	if (req.method !== 'GET' || !req.url.startsWith(self.registration.scope)) {
		return;
	}
	e.respondWith(fetch(req.url, { cache: 'no-cache', credentials: 'same-origin' }).then((r) => {
		if (r.ok) {
			const copy = r.clone();
			caches.open(CACHE).then((c) => c.put(req.url, copy));
		}
		return r;
	}).catch(() => caches.match(req.url).then((m) => m || caches.match(new URL('index.offline.html', self.registration.scope).href))));
});
self.addEventListener('message', (e) => {
	if (e.data === 'update' || e.data === 'claim') {
		self.skipWaiting();
	}
});
