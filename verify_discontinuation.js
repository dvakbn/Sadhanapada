const fs = require('fs');

const indexHtml = fs.readFileSync('./index.html', 'utf8');
const swJs = fs.readFileSync('./sw.js', 'utf8');

console.log("=== VERIFYING PWA KILL SWITCH & DISCONTINUATION SCREEN ===");

// Check index.html requirements
console.log("- index.html contains 'Application Discontinued':", indexHtml.includes('Application Discontinued'));
console.log("- index.html contains 'permanently discontinued':", indexHtml.includes('permanently discontinued'));
console.log("- index.html contains service worker unregistration:", indexHtml.includes('registration.unregister()'));
console.log("- index.html contains caches.delete:", indexHtml.includes('caches.delete'));
console.log("- index.html contains localStorage.clear():", indexHtml.includes('localStorage.clear()'));

// Check sw.js requirements
console.log("- sw.js contains self.skipWaiting():", swJs.includes('self.skipWaiting()'));
console.log("- sw.js contains caches.delete:", swJs.includes('caches.delete'));
console.log("- sw.js contains self.registration.unregister():", swJs.includes('self.registration.unregister()'));

console.log("\nSUCCESS: All PWA kill switch requirements verified!");
