/* Sadhanapada service worker: cache only the app's public static shell. */
const CACHE='sadhanapada-v10-static-only-security';
const CORE=['./','./index.html','./manifest.webmanifest','./icon-192.png','./icon-512.png','./Guided_Yogasanas.mp3','./ANGAMARDHANA.png','./PRACTICES GUIDANCE.png','./SHAKTI CHALANA.png','./SURYA KRIYA.png','./YOGASANA.png'];
const CACHE_PATHS=new Set(CORE.map(path=>new URL(path,self.registration.scope).pathname));
self.addEventListener('install',event=>{
  event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(CORE)).then(()=>self.skipWaiting()));
});
self.addEventListener('activate',event=>{
  event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(key=>key!==CACHE).map(key=>caches.delete(key)))).then(()=>self.clients.claim()));
});
self.addEventListener('fetch',event=>{
  const request=event.request;
  if(request.method!=='GET')return;
  const url=new URL(request.url);
  if(url.origin!==self.location.origin||url.search||!CACHE_PATHS.has(url.pathname))return;
  event.respondWith(
    caches.match(request,{ignoreSearch:false}).then(cached=>{
      const network=fetch(request).then(response=>{
        if(response&&(response.ok||response.type==='opaque')){
          const copy=response.clone();
          caches.open(CACHE).then(cache=>cache.put(request,copy));
        }
        return response;
      }).catch(()=>cached);
      return cached||network;
    })
  );
});