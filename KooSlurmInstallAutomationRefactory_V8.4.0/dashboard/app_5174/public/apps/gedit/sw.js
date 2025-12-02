/**
 * Service Worker for GEdit PWA
 */

const CACHE_NAME = 'gedit-app-v2';
const urlsToCache = [
  '/apps/gedit/',
  '/apps/gedit/index.html',
  '/apps/gedit/manifest.json',
  '/icon-192.png',
  '/icon-512.png',
];

// Install event
self.addEventListener('install', (event) => {
  console.log('[GEdit SW] Installing...');
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      console.log('[GEdit SW] Caching app shell');
      return cache.addAll(urlsToCache);
    })
  );
  self.skipWaiting();
});

// Activate event
self.addEventListener('activate', (event) => {
  console.log('[GEdit SW] Activating...');
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames.map((cacheName) => {
          if (cacheName.startsWith('gedit-app-') && cacheName !== CACHE_NAME) {
            console.log('[GEdit SW] Deleting old cache:', cacheName);
            return caches.delete(cacheName);
          }
        })
      );
    })
  );
  self.clients.claim();
});

// Fetch event - Network first, fallback to cache
self.addEventListener('fetch', (event) => {
  // Skip non-GET requests and non-http(s) schemes
  if (event.request.method !== 'GET' ||
      (!event.request.url.startsWith('http://') && !event.request.url.startsWith('https://'))) {
    return;
  }

  event.respondWith(
    fetch(event.request)
      .then((response) => {
        // Only cache successful responses
        if (response.status === 200) {
          const responseToCache = response.clone();

          caches.open(CACHE_NAME).then((cache) => {
            cache.put(event.request, responseToCache).catch((err) => {
              console.log('[GEdit SW] Cache put error:', err);
            });
          });
        }

        return response;
      })
      .catch(() => {
        // If network fails, try cache
        return caches.match(event.request).then((cachedResponse) => {
          if (cachedResponse) {
            return cachedResponse;
          }
          // Return a basic error response if no cache found
          return new Response('Network error', {
            status: 503,
            statusText: 'Service Unavailable'
          });
        });
      })
  );
});
