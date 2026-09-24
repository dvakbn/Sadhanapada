/* Sadhanapada service worker: keeps the app working offline */
const CACHE='sadhanapada-v6';
const CORE=['./','./index.html','./manifest.webmanifest','./icon-192.png','./icon-512.png','./Guided_Yogasanas.mp3','./ANGAMARDHANA.png','./PRACTICES GUIDANCE.png','./SHAKTI CHALANA.png','./SURYA KRIYA.png','./YOGASANA.png'];
self.addEventListener('install',e=>{
  e.waitUntil(caches.open(CACHE).then(c=>c.addAll(CORE)).then(()=>self.skipWaiting()));
});
self.addEventListener('activate',e=>{
  e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim()));
});
self.addEventListener('fetch',e=>{
  const req=e.request;
  if(req.method!=='GET')return;
  e.respondWith(
    caches.match(req,{ignoreSearch:true}).then(hit=>{
      const net=fetch(req).then(res=>{
        if(res&&(res.ok||res.type==='opaque')){const copy=res.clone();caches.open(CACHE).then(c=>c.put(req,copy))}
        return res;
      }).catch(()=>hit);
      return hit||net;
    })
  );
});
