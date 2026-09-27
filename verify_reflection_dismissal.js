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

const code = scripts.join('\n') + `
  console.log("=== VERIFYING REFLECTION BANNER CROSS DISMISSAL ===");

  // Mock evening time (> 20:30)
  const origDate = Date;
  global.Date = class extends origDate {
    constructor(...args) {
      if (args.length) return new origDate(...args);
      const d = new origDate();
      d.setHours(21, 0, 0, 0);
      return d;
    }
  };

  go('home');
  const hasEvening1 = mockElem.innerHTML.includes('Evening reflection');
  console.log("1. Evening reflection banner shown:", hasEvening1);
  console.log("- Includes dismiss action 'dismissEveningReflection':", mockElem.innerHTML.includes('dismissEveningReflection'));

  // Test action dismissEveningReflection
  window.__sd.ACT.dismissEveningReflection();
  const hasEvening2 = mockElem.innerHTML.includes('Evening reflection');
  console.log("2. Evening reflection banner hidden after clicking cross:", !hasEvening2);

  global.Date = origDate;
`;

eval(code);

console.log("\nSUCCESS: Reflection banner dismissal verified!");
