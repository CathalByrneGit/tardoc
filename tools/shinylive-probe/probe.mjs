import { chromium } from 'playwright';
const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
const p = await (await b.newContext({viewport:{width:1280,height:900}})).newPage();
const t0 = Date.now();
await p.goto('http://127.0.0.1:8811/index.html', { waitUntil: 'load' });
let appFrame = null, txt = '';
for (let i = 0; i < 120; i++) {
  await p.waitForTimeout(2000);
  for (const f of p.frames()) {
    try {
      const t = await f.innerText('body');
      if (/tardoc analytics|Result|SQL/.test(t)) { appFrame = f; txt = t; break; }
    } catch {}
  }
  if (appFrame) break;
}
if (!appFrame) { console.log('app frame never rendered'); await b.close(); process.exit(0); }
console.log(`APP RENDERED in ${((Date.now()-t0)/1000).toFixed(1)}s`);
console.log('visible:', txt.slice(0,160).replace(/\n+/g,' | '));
// Run the SQL query through R -> duckdb
try {
  await appFrame.click('#go', { timeout: 30000 });
  await appFrame.waitForSelector('table', { timeout: 90000 });
  const table = await appFrame.innerText('table');
  console.log('QUERY RAN. table:', table.replace(/\n+/g,' | ').slice(0,200));
} catch (e) { console.log('query step failed:', String(e).slice(0,140)); }
await p.screenshot({ path: 'shinylive-probe.png', fullPage: true });
console.log('total elapsed:', ((Date.now()-t0)/1000).toFixed(1) + 's');
await b.close();
