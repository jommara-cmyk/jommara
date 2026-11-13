const V="jommara-v10",CORE=["./","./index.html","./manifest.webmanifest","./icon-192.png","./icon-512.png","./apple-touch-icon.png"];
self.addEventListener("install",e=>{e.waitUntil(caches.open(V).then(c=>c.addAll(CORE)).then(()=>self.skipWaiting()))});
self.addEventListener("activate",e=>{e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k!==V).map(k=>caches.delete(k)))).then(()=>self.clients.claim()))});
self.addEventListener("fetch",e=>{const r=e.request;if(r.method!=="GET"||new URL(r.url).origin!==location.origin)return;
e.respondWith(fetch(r).then(res=>{if(res&&res.ok){const cp=res.clone();caches.open(V).then(c=>c.put(r,cp))}return res}).catch(()=>caches.match(r).then(m=>m||caches.match("./index.html"))))});

self.addEventListener("push",e=>{let d={};try{d=e.data?e.data.json():{}}catch(x){d={title:"جمّارة",body:e.data?e.data.text():""}}
e.waitUntil(self.clients.matchAll({type:"window",includeUncontrolled:true}).then(cs=>{if(cs.some(c=>c.visibilityState==="visible"&&c.focused))return;return self.registration.showNotification(d.title||"جمّارة",{body:d.body||"",icon:"icon-192.png",badge:"icon-192.png",dir:"rtl",lang:"ar",tag:d.tag||"jm",renotify:true,data:{url:d.url||"./"}})}))});
self.addEventListener("notificationclick",e=>{e.notification.close();e.waitUntil(self.clients.matchAll({type:"window",includeUncontrolled:true}).then(cs=>{for(const c of cs){if("focus"in c)return c.focus()}return self.clients.openWindow("./")}))});
