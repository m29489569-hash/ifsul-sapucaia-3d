import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright';

const ROOT = path.resolve(import.meta.dirname, '..');
const PORT = Number(process.env.WEB_SMOKE_PORT || 3456);
const BASE_URL = `http://127.0.0.1:${PORT}`;

function nextShotDir() {
  const shotsRoot = path.join(ROOT, 'shots');
  fs.mkdirSync(shotsRoot, { recursive: true });
  const existing = fs.readdirSync(shotsRoot).filter((d) => /^web-\d+$/.test(d)).sort();
  const nextNum = existing.length > 0 ? Number(existing[existing.length - 1].split('-')[1]) + 1 : 1;
  const dir = path.join(shotsRoot, `web-${String(nextNum).padStart(2, '0')}`);
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

async function waitForHealth(url, timeoutMs = 15000) {
  const t0 = Date.now();
  while (Date.now() - t0 < timeoutMs) {
    try {
      const r = await fetch(`${url}/healthz`);
      if (r.ok) return await r.json();
    } catch {}
    await new Promise((r) => setTimeout(r, 200));
  }
  throw new Error('Servidor web nao respondeu em /healthz');
}

async function checkServerContracts(meta) {
  const health = await fetch(`${BASE_URL}/healthz`);
  assert.equal(health.status, 200, '/healthz deve retornar 200');
  const hj = await health.json();
  assert.equal(hj.ok, true);

  const idx = await fetch(`${BASE_URL}/`);
  assert.equal(idx.status, 200);
  assert.match(idx.headers.get('cache-control') || '', /no-cache/i, 'index.html precisa Cache-Control: no-cache');

  const cred = await fetch(`${BASE_URL}/credits`);
  assert.equal(cred.status, 200);
  const credHtml = await cred.text();
  assert.match(credHtml, /CC0/i);
  assert.match(credHtml, /OFL/i);
  assert.match(credHtml, /ODbL/i);

  const wasmUrl = `${BASE_URL}/game/${meta.files.wasm}`;
  const resBr = await fetch(wasmUrl, { headers: { 'Accept-Encoding': 'br' } });
  assert.equal(resBr.status, 200);
  assert.equal(resBr.headers.get('content-type'), 'application/wasm');
  assert.equal(resBr.headers.get('content-encoding'), 'br');
  assert.match(resBr.headers.get('vary') || '', /Accept-Encoding/i);
  assert.match(resBr.headers.get('cache-control') || '', /immutable/i);
  await resBr.arrayBuffer();

  const resGz = await fetch(wasmUrl, { headers: { 'Accept-Encoding': 'gzip' } });
  assert.equal(resGz.status, 200);
  assert.equal(resGz.headers.get('content-encoding'), 'gzip');
  assert.match(resGz.headers.get('vary') || '', /Accept-Encoding/i);
  await resGz.arrayBuffer();
}

async function run() {
  const metaPath = path.join(ROOT, 'site', 'public', 'game', 'build-meta.json');
  assert.ok(fs.existsSync(metaPath), 'build-meta.json ausente; rode tools/build_web.sh primeiro.');
  const meta = JSON.parse(fs.readFileSync(metaPath, 'utf8'));

  const server = spawn(process.execPath, [path.join(ROOT, 'site', 'server.js')], {
    cwd: ROOT,
    env: { ...process.env, PORT: String(PORT) },
    stdio: ['ignore', 'pipe', 'pipe']
  });

  let browser;
  try {
    await waitForHealth(BASE_URL);
    await checkServerContracts(meta);

    const shotDir = nextShotDir();
    browser = await chromium.launch({
      headless: true,
      args: [
        '--enable-webgl',
        '--ignore-gpu-blocklist'
      ]
    });

    // 1. Verify WebGL2 fallback dialog when WebGL2 is unavailable
    {
      const ctxFallback = await browser.newContext({ viewport: { width: 1280, height: 720 } });
      const pageFb = await ctxFallback.newPage();
      await pageFb.addInitScript(() => {
        const origGetContext = HTMLCanvasElement.prototype.getContext;
        HTMLCanvasElement.prototype.getContext = function (type, ...rest) {
          if (type === 'webgl2') return null;
          return origGetContext.call(this, type, ...rest);
        };
      });
      await pageFb.goto(BASE_URL, { waitUntil: 'domcontentloaded' });
      await pageFb.waitForSelector('#dlg-webgl[open]', { timeout: 5000 });
      await ctxFallback.close();
    }

    // 1b. Verify Crash overlay opens with Recarregar button when engine fails to boot
    {
      const ctxCrash = await browser.newContext({ viewport: { width: 1280, height: 720 } });
      const pageCrash = await ctxCrash.newPage();
      await pageCrash.route('**/game/build-meta.json', (route) => route.abort());
      await pageCrash.goto(BASE_URL, { waitUntil: 'domcontentloaded' });
      await pageCrash.waitForSelector('#dlg-crash[open]', { timeout: 5000 });
      const btnText = await pageCrash.textContent('#btn-crash-reload');
      assert.match(btnText || '', /Recarregar/i);
      await ctxCrash.close();
    }

    // 2. Verify window.__ifsul is NOT exposed without ?test=1
    {
      const ctxProd = await browser.newContext({ viewport: { width: 1280, height: 720 } });
      const pageProd = await ctxProd.newPage();
      await pageProd.goto(BASE_URL, { waitUntil: 'domcontentloaded' });
      await pageProd.waitForFunction(() => {
        const b = document.getElementById('btn-play');
        return b && !b.disabled;
      }, { timeout: 45000 });
      const hasHook = await pageProd.evaluate(() => typeof window.__ifsul !== 'undefined');
      assert.equal(hasHook, false, 'window.__ifsul nao pode ficar ativo sem ?test=1');
      await ctxProd.close();
    }

    // 3. Main E2E run at 1366x768 with ?test=1
    const context = await browser.newContext({ viewport: { width: 1366, height: 768 } });
    const page = await context.newPage();
    const consoleErrors = [];
    page.on('pageerror', (err) => consoleErrors.push(`pageerror: ${err.message}`));
    page.on('console', (msg) => {
      if (msg.type() === 'error') {
        consoleErrors.push(`console.error: ${msg.text()}`);
      }
    });

    await page.goto(`${BASE_URL}/?test=1`, { waitUntil: 'domcontentloaded' });

    // Wait for Godot engine + scene ready
    await page.waitForFunction(() => {
      const btn = document.getElementById('btn-play');
      return btn && !btn.disabled && typeof window.__ifsul !== 'undefined';
    }, { timeout: 60000 });

    const loadTxt = await page.textContent('#load-bytes');
    assert.match(loadTxt || '', /100%/, 'Progresso real deve atingir 100%');
    await page.screenshot({ path: path.join(shotDir, '01_entry_overlay.png'), timeout: 60000 });

    // Click Play (unlocks audio + starts game)
    await page.click('#btn-play');
    await page.waitForFunction(() => window.__ifsul.getState().started === true, { timeout: 10000 });
    await page.waitForTimeout(1000);
    await page.screenshot({ path: path.join(shotDir, '02_spawn_web.png'), timeout: 60000 });

    const glInfo = await page.evaluate(() => {
      const c = document.getElementById('game-canvas');
      const gl = c.getContext('webgl2');
      if (!gl) return { glRenderer: 'unavailable' };
      const ext = gl.getExtension('WEBGL_debug_renderer_info');
      return {
        glVendor: ext ? gl.getParameter(ext.UNMASKED_VENDOR_WEBGL) : gl.getParameter(gl.VENDOR),
        glRenderer: ext ? gl.getParameter(ext.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER),
        godotRenderer: window.__ifsul.getState().renderer
      };
    });

    // Complete full 6/6 POI tour via window.__ifsul
    const initialState = await page.evaluate(() => window.__ifsul.getState());
    assert.equal(initialState.pois.length, 6, 'Esperado 6 POIs no campus');

    for (const poi of initialState.pois) {
      const [px, py, pz] = poi.position;
      await page.evaluate(([x, y, z]) => window.__ifsul.teleport(x, y + 0.2, z), [px, py, pz]);
      await page.waitForTimeout(180);
      const ok = await page.evaluate(() => window.__ifsul.interact());
      assert.equal(ok, true, `Falha ao interagir com POI ${poi.id}`);
      await page.waitForFunction(() => window.__ifsul.getState().poiModalVisible === true, { timeout: 5000 });
      await page.evaluate(() => window.__ifsul.closePoiModal());
      await page.waitForTimeout(120);
    }

    const doneState = await page.evaluate(() => window.__ifsul.getState());
    assert.equal(doneState.visitedCount, 6, 'Tour deve completar 6/6');
    assert.equal(doneState.completeVisible, true, 'Modal de conclusao deve aparecer em 6/6');
    await page.screenshot({ path: path.join(shotDir, '03_tour_complete.png'), timeout: 60000 });

    await page.evaluate(() => window.__ifsul.closeCompleteModal());
    await page.waitForTimeout(150);

    // Validate day/night + night screenshot
    await page.evaluate(() => window.__ifsul.toggleDayNight());
    await page.waitForTimeout(1800);
    await page.screenshot({ path: path.join(shotDir, '04_night_web.png'), timeout: 60000 });
    await page.evaluate(() => window.__ifsul.toggleDayNight());
    await page.waitForTimeout(1800);

    // Validate pause / resume, and while paused (pointer lock released), test web chips (mute, quality, fullscreen)
    await page.evaluate(() => window.__ifsul.togglePause());
    await page.waitForFunction(() => window.__ifsul.getState().paused === true && window.__ifsul.getState().pauseVisible === true, { timeout: 5000 });
    await page.evaluate(() => { if (document.pointerLockElement) document.exitPointerLock(); });
    await page.waitForTimeout(100);

    // Validate mute + localStorage persistence via HUD chip
    await page.click('#chip-mute');
    await page.waitForFunction(() => window.__ifsul.getState().muted === true, { timeout: 5000 });
    assert.equal(await page.evaluate(() => localStorage.getItem('ifsul.muted')), '1');
    await page.click('#chip-mute');
    await page.waitForFunction(() => window.__ifsul.getState().muted === false, { timeout: 5000 });

    // Validate quality switching + localStorage
    await page.evaluate(() => window.__ifsul.setQuality('medium'));
    await page.waitForFunction(() => window.__ifsul.getState().resolvedQuality === 'medium', { timeout: 5000 });
    assert.equal(await page.evaluate(() => localStorage.getItem('ifsul.quality')), 'medium');
    await page.evaluate(() => window.__ifsul.setQuality('high'));
    await page.waitForFunction(() => window.__ifsul.getState().resolvedQuality === 'high', { timeout: 5000 });

    await page.evaluate(() => window.__ifsul.resume());
    await page.waitForFunction(() => window.__ifsul.getState().paused === false, { timeout: 5000 });

    // Measure frametime via rAF + Godot EMA (explicitly noting software GL in headless)
    const perfSample = await page.evaluate(async () => {
      const deltas = [];
      await new Promise((resolve) => {
        let prev = performance.now();
        let count = 0;
        function tick(now) {
          deltas.push(now - prev);
          prev = now;
          count++;
          if (count >= 30) resolve();
          else requestAnimationFrame(tick);
        }
        requestAnimationFrame(tick);
      });
      const avgRafMs = deltas.reduce((a, b) => a + b, 0) / deltas.length;
      const st = window.__ifsul.getState();
      return {
        rafAvgMs: Number(avgRafMs.toFixed(2)),
        godotEmaMs: st.frametimeMs,
        godotFps: st.fps
      };
    });

    // Resize 800x600 <-> Fullscreen check
    await page.setViewportSize({ width: 800, height: 600 });
    await page.waitForTimeout(400);
    const dims800 = await page.evaluate(() => {
      const c = document.getElementById('game-canvas');
      return {
        w: c.clientWidth,
        h: c.clientHeight,
        scrollH: document.documentElement.scrollHeight,
        scrollW: document.documentElement.scrollWidth
      };
    });
    assert.equal(dims800.w, 800);
    assert.equal(dims800.h, 600);
    assert.ok(dims800.scrollH <= 600 && dims800.scrollW <= 800, 'Pagina nao pode rolar sobre o canvas');
    await page.screenshot({ path: path.join(shotDir, '05_resize_800x600.png'), timeout: 60000 });

    // Trigger fullscreen chip (exit pointer lock first so chip receives click)
    await page.evaluate(() => { if (document.pointerLockElement) document.exitPointerLock(); });
    await page.waitForTimeout(100);
    await page.click('#chip-fullscreen');
    await page.waitForTimeout(300);
    if (await page.evaluate(() => Boolean(document.fullscreenElement))) {
      await page.click('#chip-fullscreen');
      await page.waitForTimeout(300);
    }
    await page.setViewportSize({ width: 1366, height: 768 });
    await page.waitForTimeout(250);

    // Reload with cache enabled and verify persistence + clean restart
    await page.evaluate(() => {
      localStorage.setItem('ifsul.quality', 'medium');
      localStorage.setItem('ifsul.muted', '1');
    });
    await page.reload({ waitUntil: 'domcontentloaded' });
    await page.waitForFunction(() => {
      const btn = document.getElementById('btn-play');
      return btn && !btn.disabled && typeof window.__ifsul !== 'undefined';
    }, { timeout: 60000 });
    await page.click('#btn-play');
    await page.waitForFunction(() => window.__ifsul.getState().started === true, { timeout: 10000 });
    const reloadedState = await page.evaluate(() => window.__ifsul.getState());
    assert.equal(reloadedState.quality, 'medium', 'Qualidade deve persistir apos reload');
    assert.equal(reloadedState.muted, true, 'Mudo deve persistir apos reload');

    assert.equal(consoleErrors.length, 0, `Erros de console detectados:\n${consoleErrors.join('\n')}`);

    const report = {
      hash: meta.hash,
      glInfo,
      measurementMethod: 'headless_chromium_software_gl_swiftshader (NAO representa GPU real de usuario)',
      perfSample,
      consoleErrors: consoleErrors.length,
      checks: {
        webgl2Fallback: true,
        hookHiddenWithoutTestParam: true,
        tour6of6: true,
        muteAndQualityPersisted: true,
        pauseResume: true,
        resize800x600AndFullscreen: true,
        reloadWithCache: true,
        wasmMimeAndCompression: true
      }
    };
    fs.writeFileSync(path.join(shotDir, 'meta.json'), JSON.stringify(report, null, 2) + '\n');
    console.log('WEB_SMOKE_PASS:', JSON.stringify(report));
  } finally {
    if (browser) await browser.close();
    server.kill('SIGTERM');
  }
}

run().catch((err) => {
  console.error('WEB_SMOKE_FAIL:', err);
  process.exit(1);
});
