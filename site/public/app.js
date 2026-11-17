(() => {
  const canvas = document.getElementById('game-canvas');
  const overlay = document.getElementById('entry-overlay');
  const btnPlay = document.getElementById('btn-play');
  const loadStatus = document.getElementById('load-status');
  const loadBytes = document.getElementById('load-bytes');
  const loadFill = document.getElementById('load-fill');
  const loadProgress = document.getElementById('load-progressbar');

  const webChips = document.getElementById('web-chips');
  const chipFps = document.getElementById('chip-fps');
  const chipQuality = document.getElementById('chip-quality');
  const chipMute = document.getElementById('chip-mute');
  const chipFullscreen = document.getElementById('chip-fullscreen');

  const dlgWebgl = document.getElementById('dlg-webgl');
  const dlgCrash = document.getElementById('dlg-crash');
  const dlgCrashMsg = document.getElementById('dlg-crash-msg');

  const QUALITY_ORDER = ['auto', 'high', 'medium', 'low'];
  const QUALITY_LABEL = {
    auto: 'Auto',
    high: 'Alta',
    medium: 'Média',
    low: 'Baixa'
  };

  let savedQuality = localStorage.getItem('ifsul.quality') || 'auto';
  if (!QUALITY_ORDER.includes(savedQuality)) savedQuality = 'auto';
  let savedMuted = localStorage.getItem('ifsul.muted') === '1';
  window.__ifsulInitPrefs = { quality: savedQuality, muted: savedMuted };

  let engineReady = false;
  let godotReady = false;
  let initialSyncDone = false;
  let gameStarted = false;
  let latestState = { started: false, paused: false, modalOpen: false, muted: savedMuted, quality: savedQuality, resolvedQuality: 'medium', fps: 0 };
  let wasPointerLocked = false;
  let expectedTotalBytes = 0;

  async function yieldToMain() {
    if ('scheduler' in window && 'yield' in window.scheduler) {
      await window.scheduler.yield();
    } else {
      await new Promise((resolve) => setTimeout(resolve, 0));
    }
  }

  function showCrash(msg) {
    if (dlgCrashMsg && msg) dlgCrashMsg.textContent = msg;
    if (dlgCrash && !dlgCrash.open) {
      try { dlgCrash.showModal(); } catch { dlgCrash.setAttribute('open', ''); }
    }
  }

  document.getElementById('btn-webgl-reload')?.addEventListener('click', () => location.reload());
  document.getElementById('btn-crash-reload')?.addEventListener('click', () => location.reload());

  // WebGL2 availability check before touching Godot Engine
  const hasWebGL2 = (() => {
    try {
      const testCanvas = document.createElement('canvas');
      return Boolean(window.WebGL2RenderingContext && testCanvas.getContext('webgl2'));
    } catch {
      return false;
    }
  })();

  if (!hasWebGL2) {
    loadStatus.textContent = 'WebGL2 não detectado neste dispositivo.';
    if (dlgWebgl && !dlgWebgl.open) {
      try { dlgWebgl.showModal(); } catch { dlgWebgl.setAttribute('open', ''); }
    }
    return;
  }

  function updateChipsUI(state) {
    latestState = { ...latestState, ...state };
    const qMode = latestState.quality || savedQuality;
    const qRes = latestState.resolvedQuality || 'high';
    chipQuality.textContent = qMode === 'auto'
      ? `Qualidade: Auto (${QUALITY_LABEL[qRes] || qRes})`
      : `Qualidade: ${QUALITY_LABEL[qMode] || qMode}`;

    const muted = Boolean(latestState.muted);
    chipMute.textContent = muted ? 'Som: MUDO' : 'Som: ON';
    chipMute.setAttribute('aria-pressed', muted ? 'true' : 'false');

    const fpsVal = Number(latestState.fps || 0);
    chipFps.textContent = fpsVal > 0 ? `${fpsVal} FPS` : '-- FPS';

    const fsActive = Boolean(document.fullscreenElement);
    chipFullscreen.textContent = fsActive ? 'Sair tela cheia' : 'Tela cheia';
    chipFullscreen.setAttribute('aria-pressed', fsActive ? 'true' : 'false');
  }

  function unlockAudio() {
    try {
      const Ctx = window.AudioContext || window.webkitAudioContext;
      if (Ctx) {
        if (!window.__ifsulAudioCtx) window.__ifsulAudioCtx = new Ctx();
        if (window.__ifsulAudioCtx.state === 'suspended') {
          window.__ifsulAudioCtx.resume().catch(() => {});
        }
      }
    } catch {}
  }

  function requestCanvasLock() {
    try {
      if (document.pointerLockElement !== canvas && canvas.requestPointerLock) {
        const res = canvas.requestPointerLock();
        if (res && typeof res.catch === 'function') res.catch(() => {});
      }
    } catch {}
  }

  function startOrEnterGame() {
    if (!godotReady || !window.__ifsulGodot || gameStarted) return;
    gameStarted = true;
    overlay.setAttribute('data-hidden', 'true');
    webChips.setAttribute('data-visible', 'true');
    canvas.focus({ preventScroll: true });
    requestCanvasLock();

    if (latestState.quality !== savedQuality) {
      window.__ifsulGodot.setQuality(savedQuality);
    }
    if (Boolean(latestState.muted) !== savedMuted) {
      window.__ifsulGodot.setMuted(savedMuted);
    }
    window.__ifsulGodot.start();
  }

  btnPlay.addEventListener('click', startOrEnterGame);

  chipQuality.addEventListener('click', () => {
    const idx = QUALITY_ORDER.indexOf(savedQuality);
    savedQuality = QUALITY_ORDER[(idx + 1) % QUALITY_ORDER.length];
    localStorage.setItem('ifsul.quality', savedQuality);
    if (window.__ifsulGodot) window.__ifsulGodot.setQuality(savedQuality);
    updateChipsUI({ quality: savedQuality });
  });

  chipMute.addEventListener('click', () => {
    savedMuted = !savedMuted;
    localStorage.setItem('ifsul.muted', savedMuted ? '1' : '0');
    if (window.__ifsulGodot) window.__ifsulGodot.setMuted(savedMuted);
    updateChipsUI({ muted: savedMuted });
  });

  chipFullscreen.addEventListener('click', async () => {
    try {
      if (!document.fullscreenElement) {
        await document.documentElement.requestFullscreen();
      } else {
        await document.exitFullscreen();
      }
    } catch {}
    updateChipsUI({});
  });

  document.addEventListener('fullscreenchange', () => {
    updateChipsUI({});
    window.dispatchEvent(new Event('resize'));
  });

  document.addEventListener('pointerlockchange', () => {
    const locked = document.pointerLockElement === canvas;
    if (wasPointerLocked && !locked && gameStarted && !latestState.paused && !latestState.modalOpen) {
      if (window.__ifsulGodot) window.__ifsulGodot.setPaused(true);
    }
    wasPointerLocked = locked;
  });

  // Coordinate responsive resizing across ResizeObserver, visualViewport, orientation & DPR changes
  const stage = document.getElementById('stage');
  let lastStageW = 0;
  let lastStageH = 0;
  let resizeRaf = 0;
  let lastHudMetrics = null;

  function applyHudMetrics() {
    if (!lastHudMetrics || !canvas.clientHeight) return;
    const topPx = Math.round(lastHudMetrics.topRatio * canvas.clientHeight) + 8;
    webChips.style.setProperty('--chips-top', `${Math.max(40, topPx)}px`);
    if (typeof lastHudMetrics.fontRatio === 'number') {
      const fontPx = Math.max(11, Math.min(16, Math.round(lastHudMetrics.fontRatio * canvas.clientHeight)));
      webChips.style.setProperty('--chip-font', `${fontPx}px`);
    }
  }

  function syncViewport() {
    if (resizeRaf) return;
    resizeRaf = requestAnimationFrame(() => {
      resizeRaf = 0;
      applyHudMetrics();
      window.dispatchEvent(new Event('resize'));
    });
  }

  if (stage && 'ResizeObserver' in window) {
    new ResizeObserver((entries) => {
      const rect = entries[0]?.contentRect;
      const w = Math.round(rect ? rect.width : stage.clientWidth);
      const h = Math.round(rect ? rect.height : stage.clientHeight);
      if (w !== lastStageW || h !== lastStageH) {
        lastStageW = w;
        lastStageH = h;
        syncViewport();
      }
    }).observe(stage);
  }
  window.visualViewport?.addEventListener('resize', syncViewport);
  window.addEventListener('orientationchange', () => setTimeout(syncViewport, 120));
  window.addEventListener('wheel', (e) => {
    if (e.ctrlKey && e.target === canvas) e.preventDefault();
  }, { passive: false });

  // Shell bridge consumed by scripts/main.gd
  window.__ifsulShell = {
    onHudMetrics(metrics) {
      if (!metrics || typeof metrics.topRatio !== 'number') return;
      lastHudMetrics = metrics;
      applyHudMetrics();
    },
    onBootProgress(pct, statusText) {
      if (godotReady) return;
      const clamped = Math.max(0, Math.min(99, Math.round(Number(pct) || 80)));
      loadFill.removeAttribute('data-indeterminate');
      loadFill.style.setProperty('--progress-scale', String(clamped / 100));
      loadProgress.setAttribute('aria-valuenow', String(clamped));
      if (statusText) loadStatus.textContent = statusText;
      if (expectedTotalBytes > 0) {
        const mb = (expectedTotalBytes / 1048576).toFixed(1);
        loadBytes.textContent = `${clamped}% • ${mb} / ${mb} MB`;
      } else {
        loadBytes.textContent = `${clamped}%`;
      }
    },
    onGodotReady() {
      godotReady = true;
      initialSyncDone = true;
      loadFill.removeAttribute('data-indeterminate');
      loadFill.style.setProperty('--progress-scale', '1');
      loadProgress.setAttribute('aria-valuenow', '100');
      loadStatus.textContent = 'Câmpus pronto para visitação';
      if (expectedTotalBytes > 0) {
        const mb = (expectedTotalBytes / 1048576).toFixed(1);
        loadBytes.textContent = `100% • ${mb} MB`;
      } else {
        loadBytes.textContent = '100%';
      }
      btnPlay.disabled = false;
      btnPlay.textContent = 'Explorar Câmpus';
    },
    onGodotState(state) {
      if (initialSyncDone && typeof state.muted === 'boolean' && state.muted !== savedMuted) {
        savedMuted = state.muted;
        localStorage.setItem('ifsul.muted', savedMuted ? '1' : '0');
      }
      updateChipsUI(state);
    },
    exposeTestHook() {
      if (new URLSearchParams(location.search).get('test') !== '1' || !window.__ifsulRaw) return;
      const raw = window.__ifsulRaw;
      window.__ifsul = {
        getState() { return { ...latestState }; },
        get fps() { return latestState.fps || 0; },
        get position() { return latestState.position || [0, 0, 0]; },
        teleport(x, y, z) { raw.teleport(x, y, z); },
        interact() {
          raw.interact();
          return Boolean(latestState.poiModalVisible);
        },
        closePoiModal() {
          raw.closePoiModal();
          return !latestState.poiModalVisible;
        },
        closeCompleteModal() {
          raw.closeCompleteModal();
          return !latestState.completeVisible;
        },
        setQuality(q) {
          savedQuality = q;
          localStorage.setItem('ifsul.quality', q);
          raw.setQuality(q);
        },
        toggleMute() { raw.toggleMute(); },
        togglePause() { raw.togglePause(); },
        resume() { raw.resume(); },
        toggleDayNight() { raw.toggleDayNight(); },
        toggleDrone() {
          raw.toggleDrone();
          return Boolean(latestState.isDrone);
        },
        restartTour() { raw.restartTour(); }
      };
    }
  };

  async function bootEngine() {
    try {
      let meta = window.__BUILD_META__ || null;
      if (!meta) {
        const metaRes = await fetch('/game/build-meta.json', { cache: 'no-cache' });
        if (!metaRes.ok) throw new Error('Falha ao carregar metadados da build.');
        meta = await metaRes.json();
      }
      expectedTotalBytes = meta?.sizes?.total || 0;

      await new Promise((resolve, reject) => {
        const sc = document.createElement('script');
        sc.src = `/game/${meta.files.js}`;
        sc.onload = resolve;
        sc.onerror = () => reject(new Error('Falha ao carregar runtime JavaScript da Godot.'));
        document.head.appendChild(sc);
      });

      const fileSizes = {};
      if (meta?.sizes?.wasm && meta?.executable) {
        fileSizes[`${meta.executable}.wasm`] = meta.sizes.wasm;
      }
      if (meta?.sizes?.pck && meta?.mainPack) {
        fileSizes[meta.mainPack] = meta.sizes.pck;
      }

      let lastProgressUiAt = 0;
      const engine = new Engine({
        canvas,
        executable: meta.executable,
        mainPack: meta.mainPack,
        fileSizes,
        canvasResizePolicy: 2,
        focusCanvas: false,
        onProgress(current, total) {
          if (godotReady) return;
          const denom = total > 0 ? total : expectedTotalBytes;
          const ratio = denom > 0 ? Math.min(1, current / denom) : 0;
          const now = performance.now();
          if (ratio < 0.995 && now - lastProgressUiAt < 100) return;
          lastProgressUiAt = now;
          if (denom > 0) {
            const pct = Math.min(80, Math.round(ratio * 80));
            const curMB = (Math.min(current, denom) / 1048576).toFixed(1);
            const totMB = (denom / 1048576).toFixed(1);
            loadFill.removeAttribute('data-indeterminate');
            loadFill.style.setProperty('--progress-scale', String(pct / 100));
            loadProgress.setAttribute('aria-valuenow', String(pct));
            loadStatus.textContent = ratio >= 0.995
              ? 'Inicializando motor 3D...'
              : 'Baixando arquivos do câmpus...';
            loadBytes.textContent = `${pct}% • ${curMB} / ${totMB} MB`;
          } else {
            const curMB = (current / 1048576).toFixed(1);
            loadFill.setAttribute('data-indeterminate', 'true');
            loadStatus.textContent = 'Baixando arquivos do câmpus...';
            loadBytes.textContent = `${curMB} MB`;
          }
        },
        onExit(code) {
          if (code !== 0) {
            showCrash(`O motor 3D encerrou com código ${code}. Clique abaixo para recarregar.`);
          }
        }
      });

      engineReady = true;
      await yieldToMain();
      await engine.startGame({
        canvas,
        executable: meta.executable,
        mainPack: meta.mainPack
      });
    } catch (err) {
      showCrash(err?.message || 'Erro inesperado ao iniciar o câmpus 3D.');
    }
  }

  window.addEventListener('error', (e) => {
    if (engineReady && !godotReady) {
      showCrash(`Erro de execução: ${e.message || 'falha desconhecida'}`);
    }
  });

  updateChipsUI({ quality: savedQuality, muted: savedMuted });
  bootEngine();
})();
