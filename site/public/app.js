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

  let engineReady = false;
  let godotReady = false;
  let initialSyncDone = false;
  let gameStarted = false;
  let latestState = { started: false, paused: false, modalOpen: false, muted: savedMuted, quality: savedQuality, resolvedQuality: 'high', fps: 0 };
  let wasPointerLocked = false;
  let expectedTotalBytes = 0;

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
    if (!godotReady || !window.__ifsulGodot) return;
    unlockAudio();
    gameStarted = true;
    overlay.setAttribute('data-hidden', 'true');
    webChips.setAttribute('data-visible', 'true');
    canvas.focus({ preventScroll: true });
    window.__ifsulGodot.setQuality(savedQuality);
    window.__ifsulGodot.setMuted(savedMuted);
    window.__ifsulGodot.start();
    requestCanvasLock();
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

  // Coordinate responsive resizing across visualViewport, orientation & DPR changes
  function syncViewport() {
    window.dispatchEvent(new Event('resize'));
  }
  window.visualViewport?.addEventListener('resize', syncViewport);
  window.addEventListener('orientationchange', () => setTimeout(syncViewport, 120));
  window.addEventListener('wheel', (e) => {
    if (e.ctrlKey && e.target === canvas) e.preventDefault();
  }, { passive: false });

  // Shell bridge consumed by scripts/main.gd
  window.__ifsulShell = {
    onGodotReady() {
      godotReady = true;
      if (window.__ifsulGodot) {
        window.__ifsulGodot.setQuality(savedQuality);
        window.__ifsulGodot.setMuted(savedMuted);
      }
      initialSyncDone = true;
      loadFill.removeAttribute('data-indeterminate');
      loadFill.style.setProperty('--progress', '100%');
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
      const metaRes = await fetch('/game/build-meta.json', { cache: 'no-cache' });
      if (!metaRes.ok) throw new Error('Falha ao carregar metadados da build.');
      const meta = await metaRes.json();
      expectedTotalBytes = meta?.sizes?.total || 0;

      await new Promise((resolve, reject) => {
        const sc = document.createElement('script');
        sc.src = `/game/${meta.files.js}`;
        sc.onload = resolve;
        sc.onerror = () => reject(new Error('Falha ao carregar runtime JavaScript da Godot.'));
        document.head.appendChild(sc);
      });

      const engine = new Engine({
        canvas,
        executable: meta.executable,
        mainPack: meta.mainPack,
        canvasResizePolicy: 2,
        focusCanvas: true,
        onProgress(current, total) {
          const denom = total > 0 ? total : expectedTotalBytes;
          if (denom > 0) {
            const pct = Math.min(99, Math.round((current / denom) * 100));
            const curMB = (current / 1048576).toFixed(1);
            const totMB = (denom / 1048576).toFixed(1);
            loadFill.removeAttribute('data-indeterminate');
            loadFill.style.setProperty('--progress', `${pct}%`);
            loadProgress.setAttribute('aria-valuenow', String(pct));
            loadStatus.textContent = 'Baixando arquivos do câmpus...';
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
