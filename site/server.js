const express = require('express');
const fs = require('fs');
const path = require('path');

const app = express();
const PORT = Number(process.env.PORT || 3000);
const PUBLIC_DIR = path.join(__dirname, 'public');
const GAME_DIR = path.join(PUBLIC_DIR, 'game');

app.disable('x-powered-by');

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.mjs': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.pck': 'application/octet-stream',
  '.woff2': 'font/woff2',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon'
};

function readBuildMeta() {
  try {
    const raw = fs.readFileSync(path.join(GAME_DIR, 'build-meta.json'), 'utf8');
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function escapeHtml(s) {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function renderCreditsMarkdown(md) {
  const lines = md.split(/\r?\n/);
  const items = [];
  let title = 'Créditos e Licenças';
  for (const raw of lines) {
    const line = raw.trim();
    if (!line) continue;
    if (line.startsWith('# ')) {
      title = line.slice(2).trim();
      continue;
    }
    if (line.startsWith('- ')) {
      let body = escapeHtml(line.slice(2).trim());
      body = body.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');
      body = body.replace(/`([^`]+?)`/g, '<code>$1</code>');
      body = body.replace(/(https?:\/\/[^\s<]+)/g, '<a href="$1" target="_blank" rel="noopener noreferrer">$1</a>');
      items.push(`<li>${body}</li>`);
    }
  }
  return { title, listHtml: items.join('\n') };
}

app.get('/healthz', (_req, res) => {
  const meta = readBuildMeta();
  res.setHeader('Cache-Control', 'no-cache');
  res.status(200).json({ ok: true, version: meta ? meta.hash : null });
});

app.get('/credits', (_req, res) => {
  const candidates = [
    path.join(__dirname, '..', 'docs', 'CREDITS.md'),
    path.join(__dirname, '..', 'CREDITS.md')
  ];
  let md = '# Créditos dos Assets\n';
  for (const p of candidates) {
    if (fs.existsSync(p)) {
      md = fs.readFileSync(p, 'utf8');
      break;
    }
  }
  const { title, listHtml } = renderCreditsMarkdown(md);
  res.setHeader('Cache-Control', 'no-cache');
  res.type('text/html; charset=utf-8').send(`<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${escapeHtml(title)} — IFSul Sapucaia 3D</title>
  <link rel="stylesheet" href="/styles.css">
</head>
<body class="credits-page">
  <main class="credits-card">
    <div class="plaque-stripe" aria-hidden="true"></div>
    <header class="credits-head">
      <a class="chip-btn" href="/">← Voltar ao Câmpus 3D</a>
      <h1>${escapeHtml(title)}</h1>
      <p>Recursos 100% self-hosted e licenças públicas utilizadas neste projeto.</p>
    </header>
    <ul class="credits-list">${listHtml}</ul>
  </main>
</body>
</html>`);
});

// Serve pre-compressed .br / .gz for .wasm, .pck, .js and static assets
app.use((req, res, next) => {
  if (req.method !== 'GET' && req.method !== 'HEAD') return next();

  const cleanPath = decodeURIComponent(req.path);
  if (cleanPath === '/' || cleanPath === '/index.html') {
    const htmlPath = path.join(PUBLIC_DIR, 'index.html');
    let html = fs.readFileSync(htmlPath, 'utf8');
    const meta = readBuildMeta();
    if (meta) {
      const preloads = [
        `<link rel="preload" href="/fonts/archivo-black-latin.woff2" as="font" type="font/woff2" crossorigin>`,
        `<link rel="preload" href="/fonts/inter-latin.woff2" as="font" type="font/woff2" crossorigin>`,
        `<link rel="preload" as="script" href="/game/${meta.files.js}">`,
        `<script>window.__BUILD_META__=${JSON.stringify(meta)};</script>`
      ].join('\n  ');
      html = html.replace('</head>', `  ${preloads}\n</head>`);
    }
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.setHeader('Cache-Control', 'no-cache');
    return res.send(html);
  }

  const relPath = cleanPath.replace(/^\/+/, '');
  const fullPath = path.resolve(PUBLIC_DIR, relPath);
  if (!fullPath.startsWith(PUBLIC_DIR)) return res.status(403).end();

  if (!fs.existsSync(fullPath) || fs.statSync(fullPath).isDirectory()) {
    return next();
  }

  const ext = path.extname(fullPath).toLowerCase();
  const mime = MIME_TYPES[ext] || 'application/octet-stream';
  res.setHeader('Content-Type', mime);

  const isVersionedGame = /^\/game\/ifsul\.[0-9a-f]{8}\.(js|wasm|pck|audio\.worklet\.js|audio\.position\.worklet\.js)$/i.test(cleanPath);
  const isFont = cleanPath.startsWith('/fonts/') && ext === '.woff2';
  if (isVersionedGame || isFont) {
    res.setHeader('Cache-Control', 'public, max-age=31536000, immutable');
  } else {
    res.setHeader('Cache-Control', 'no-cache');
  }

  const acceptEnc = String(req.headers['accept-encoding'] || '');
  if (/\bbr\b/i.test(acceptEnc) && fs.existsSync(`${fullPath}.br`)) {
    res.setHeader('Content-Encoding', 'br');
    res.setHeader('Vary', 'Accept-Encoding');
    return res.sendFile(`${fullPath}.br`);
  }
  if (/\bgzip\b/i.test(acceptEnc) && fs.existsSync(`${fullPath}.gz`)) {
    res.setHeader('Content-Encoding', 'gzip');
    res.setHeader('Vary', 'Accept-Encoding');
    return res.sendFile(`${fullPath}.gz`);
  }

  return res.sendFile(fullPath);
});

app.use((_req, res) => {
  res.status(404).type('text/plain; charset=utf-8').send('404 Not Found');
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`IFSul Sapucaia 3D server listening on http://localhost:${PORT}`);
});
