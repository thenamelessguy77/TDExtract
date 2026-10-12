// Run after exporting and starting the Python HTTP server on port 8000.
const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.launch({executablePath: '/usr/bin/chromium', headless: true, args: ['--no-sandbox', '--enable-unsafe-swiftshader']});
  for (const touch of [false, true]) {
    const context = await browser.newContext({viewport: {width:touch ? 390 : 480,height:touch ? 844 : 800}, hasTouch:touch});
    const page = await context.newPage();
    const failures = [];
    page.on('pageerror', e => failures.push(e.message));
    page.on('console', m => { if (/SCRIPT ERROR|Parse Error|ERROR:/.test(m.text())) failures.push(m.text()); });
    page.on('response', r => { if(r.status() >= 400) failures.push(`${r.status()} ${r.url()}`); });
    await page.goto(process.env.TDEXTRACT_TEST_URL || 'http://127.0.0.1:8000', {waitUntil:'networkidle'});
    await page.waitForFunction(() => !document.querySelector('#status'), {timeout:60000});
    const canvas = page.locator('canvas');
    const viewport = page.viewportSize();
    const scale = Math.min(viewport.width/480, viewport.height/800);
    const offsetX = (viewport.width - 480*scale)/2;
    const offsetY = (viewport.height - 800*scale)/2;
    const before = await canvas.screenshot();
    // Clicking a reachable floor region exercises the actual mouse/touch event path.
    if (touch) await page.touchscreen.tap(offsetX+78*scale,offsetY+218*scale);
    else await page.mouse.click(78,218);
    await page.waitForTimeout(300);
    const after = await canvas.screenshot();
    if (before.equals(after)) throw Error('Grid input did not change the rendered game');
    const idle = await canvas.screenshot();
    await page.waitForTimeout(500);
    if (!idle.equals(await canvas.screenshot())) throw Error('World changed while idle');
    // New Raid control must also work with both input types.
    if (touch) await page.touchscreen.tap(offsetX+380*scale,offsetY+38*scale);
    else await page.mouse.click(380,38);
    await page.waitForTimeout(300);
    if (idle.equals(await canvas.screenshot())) throw Error('New Raid input failed');
    if (failures.length) throw Error(failures.join('\n'));
    await page.screenshot({path:`build/web/${touch ? 'touch' : 'mouse'}-smoke.png`});
    console.log(`PASS: WebAssembly startup, ${touch ? 'touch' : 'mouse'} grid input, idle freeze, new raid, no browser/script errors`);
    await context.close();
  }
  await browser.close();
})().catch(e => {console.error(e); process.exit(1);});
