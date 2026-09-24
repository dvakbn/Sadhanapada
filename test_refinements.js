const fs = require('fs');

const html = fs.readFileSync('./index.html', 'utf8');

const scripts = [];
const re = /<script>([\s\S]*?)<\/script>/g;
let match;
while ((match = re.exec(html)) !== null) {
  scripts.push(match[1]);
}

global.window = global;
global.window.addEventListener = () => {};
global.window.scrollTo = () => {};

const mockElem = {
  classList: { add: () => {}, remove: () => {}, contains: () => false },
  style: {},
  innerHTML: '',
  getBoundingClientRect: () => ({ height: 100, top: 0 }),
  addEventListener: () => {},
  querySelectorAll: () => []
};

global.document = {
  documentElement: { getAttribute: () => 'light', setAttribute: () => {}, style: {} },
  getElementById: () => mockElem,
  querySelector: () => mockElem,
  querySelectorAll: () => [],
  addEventListener: () => {},
  removeEventListener: () => {}
};
global.view = mockElem;
global.sheet = mockElem;
global.navigator = { userAgent: 'Mozilla/5.0 (iPhone)' };
global.location = { hash: '#/home' };
global.localStorage = { getItem: () => null, setItem: () => {}, removeItem: () => {} };
global.requestAnimationFrame = (cb) => cb();
global.setTimeout = (cb) => cb();

scripts.forEach((code) => eval(code));

function testRoute(r) {
  window.__sd.go(r);
  console.log(`Route '${r}' rendered HTML length:`, mockElem.innerHTML.length);
}

testRoute('home');
testRoute('extras');
testRoute('extras/diet');
testRoute('extras/contacts');
testRoute('settings');

console.log("SUCCESS: All routes verified!");
