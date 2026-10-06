/* Kill switch Service Worker: Purges cached assets and unregisters */
const KILL_CACHE = 'discontinued-v1';

self.addEventListener('install', (e) => {
  self.skipWaiting();
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then((keys) => {
      return Promise.all(keys.map((k) => caches.delete(k)));
    }).then(() => {
      return self.clients.claim();
    }).then(() => {
      return self.registration.unregister();
    })
  );
});

self.addEventListener('fetch', (e) => {
  if (e.request.method !== 'GET') return;
  e.respondWith(
    caches.keys().then((keys) => {
      return Promise.all(keys.map((k) => caches.delete(k)));
    }).then(() => {
      return new Response(
        '<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><title>Application Discontinued</title><meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover"><meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate"><style>body{margin:0;min-height:100vh;background:#131A1B;color:#E7EBE6;font-family:system-ui,-apple-system,sans-serif;display:grid;place-items:center;text-align:center;padding:24px;box-sizing:border-box}.card{max-width:440px;width:100%;background:#1A2223;padding:40px 30px;border-radius:22px;box-shadow:0 4px 24px rgba(0,0,0,0.2);border:1px solid rgba(128,128,128,0.15)}h1{font-size:26px;font-weight:400;margin:0 0 12px}p{color:#AAB5B2;font-size:15px;line-height:1.6;margin:0}</style></head><body><div class="card"><h1>Application Discontinued</h1><p>This application has been permanently discontinued. All cached assets and local storage have been cleared.</p></div><script>if("serviceWorker"in navigator){navigator.serviceWorker.getRegistrations().then(rs=>{for(let r of rs)r.unregister()})}if("caches"in window){caches.keys().then(ks=>{for(let k of ks)caches.delete(k)})}try{localStorage.clear()}catch(e){}try{sessionStorage.clear()}catch(e){}</script></body></html>',
        { headers: { 'Content-Type': 'text/html', 'Cache-Control': 'no-cache, no-store, must-revalidate' } }
      );
    })
  );
});
