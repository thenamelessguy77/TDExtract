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
    const hudClip = {x:offsetX,y:offsetY,width:480*scale,height:160*scale};
    const hudBefore = await page.screenshot({clip:hudClip});
    const mapBefore = await canvas.screenshot();
    const client = touch ? await context.newCDPSession(page) : null;
    async function drag(dx,dy) {
      const start = {x:offsetX+240*scale,y:offsetY+380*scale};
      const end = {x:start.x+dx*scale,y:start.y+dy*scale};
      if(touch) {
        await client.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[start]});
        await client.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[end]});
        await client.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
      } else {
        await page.mouse.move(start.x,start.y);
        await page.mouse.down();
        await page.mouse.move(end.x,end.y,{steps:5});
        await page.mouse.up();
      }
      await page.waitForTimeout(150);
    }
    await drag(70,70);
    const firstPan = await canvas.screenshot();
    await drag(-140,-140);
    const secondPan = await canvas.screenshot();
    if(mapBefore.equals(firstPan) && firstPan.equals(secondPan)) throw Error('Map dragging failed');
    if(!hudBefore.equals(await page.screenshot({clip:hudClip}))) throw Error('Panning changed HP/AP/ticks or moved the player');
    if(!touch) {
      await page.mouse.move(offsetX+240*scale,offsetY+380*scale);
      const wheelBefore = await canvas.screenshot();
      await page.mouse.wheel(0,144);
      await page.waitForTimeout(150);
      const wheelDown = await canvas.screenshot();
      await page.mouse.wheel(0,-288);
      await page.waitForTimeout(150);
      const wheelUp = await canvas.screenshot();
      if(wheelBefore.equals(wheelDown) && wheelDown.equals(wheelUp)) throw Error('Mouse wheel scrolling failed');
      if(!hudBefore.equals(await page.screenshot({clip:hudClip}))) throw Error('Mouse wheel advanced the world');
    }

    const bodyPreview = await canvas.screenshot();
    async function tapLogical(x,y) {
      if(touch) await page.touchscreen.tap(offsetX+x*scale,offsetY+y*scale);
      else await page.mouse.click(offsetX+x*scale,offsetY+y*scale);
      await page.waitForTimeout(100);
    }
    await tapLogical(240,556);
    const headPreview = await canvas.screenshot();
    if(bodyPreview.equals(headPreview)) throw Error('Head shot selector did not update preview');
    await tapLogical(388,556);
    if(headPreview.equals(await canvas.screenshot())) throw Error('Burst selector did not update preview');
    if(!hudBefore.equals(await page.screenshot({clip:hudClip}))) throw Error('Choosing a shot mode spent AP or time');
    await tapLogical(92,556);
    const statusClip = {x:offsetX+24*scale,y:offsetY+62*scale,width:432*scale,height:24*scale};
    const intelClip = {x:offsetX+24*scale,y:offsetY+116*scale,width:432*scale,height:42*scale};
    const statusUnchanged = await page.screenshot({clip:statusClip});
    const intelUnchanged = await page.screenshot({clip:intelClip});
    for (const weapon of [1,2,3,4,0]) {
      const previous = await canvas.screenshot();
      await tapLogical(90,38);
      await tapLogical(90,73+27*weapon);
      if(previous.equals(await canvas.screenshot())) throw Error('Weapon dropdown did not select weapon '+weapon);
      if(!statusUnchanged.equals(await page.screenshot({clip:statusClip})) || !intelUnchanged.equals(await page.screenshot({clip:intelClip}))) throw Error('Changing pre-raid weapon changed health/AP/time');
      if(weapon === 2 || weapon === 3) {
        const singleShot = await canvas.screenshot();
        await tapLogical(388,556);
        if(!singleShot.equals(await canvas.screenshot())) throw Error('Shotgun/sniper allowed burst');
      }
    }
    const noBleeding = await canvas.screenshot();
    await tapLogical(184,610);
    if(!noBleeding.equals(await canvas.screenshot())) throw Error('Bandage button spent an action without bleeding');
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
    console.log(`PASS: WebAssembly startup, ${touch ? 'touch' : 'mouse'} drag panning without advancing time, shot-mode controls, five weapon dropdown choices without spending time/AP, disabled unsupported bursts and unnecessary bandaging, grid input, idle freeze, new raid, no browser/script errors`);
    await context.close();
  }
  await browser.close();
})().catch(e => {console.error(e); process.exit(1);});
