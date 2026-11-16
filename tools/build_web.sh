#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Locate Godot console binary
GODOT_BIN="${GODOT_BIN:-}"
if [ -z "$GODOT_BIN" ]; then
  if [ -f "/d/Downloads/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe" ]; then
    GODOT_BIN="/d/Downloads/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe"
  elif command -v godot4 >/dev/null 2>&1; then
    GODOT_BIN="godot4"
  elif command -v godot >/dev/null 2>&1; then
    GODOT_BIN="godot"
  else
    echo "ERRO: Godot nao encontrado. Defina GODOT_BIN." >&2
    exit 1
  fi
fi

RAW_VER="$("$GODOT_BIN" --version | head -n1 | tr -d '\r')"
# e.g. 4.7.stable.official.5b4e0cb0f -> 4.7.stable and 4.7-stable
TEMPLATE_VER="$(echo "$RAW_VER" | awk -F. '{print $1"."$2"."$3}')"
TAG_VER="${TEMPLATE_VER/./-}" # wait: 4.7.stable -> only replace second dot -> handled via sed
TAG_VER="$(echo "$TEMPLATE_VER" | sed 's/\.\([^.]*\)$/-\1/')"

# Determine Godot export_templates directory (Windows MSYS/Git Bash vs Linux/macOS)
if [ -n "${APPDATA:-}" ]; then
  if command -v cygpath >/dev/null 2>&1; then
    TPL_BASE="$(cygpath -u "$APPDATA")/Godot/export_templates"
  else
    TPL_BASE="$APPDATA/Godot/export_templates"
  fi
elif [ "$(uname -s)" = "Darwin" ]; then
  TPL_BASE="$HOME/Library/Application Support/Godot/export_templates"
else
  TPL_BASE="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates"
fi

TPL_DIR="$TPL_BASE/$TEMPLATE_VER"

if [ ! -f "$TPL_DIR/web_nothreads_release.zip" ] && [ ! -f "$TPL_DIR/web_release.zip" ]; then
  echo "[build_web] Export templates ausentes em $TPL_DIR. Instalando $TAG_VER..."
  mkdir -p "$TPL_DIR"
  TPZ_NAME="Godot_v${TAG_VER}_export_templates.tpz"
  TMP_DIR_U="${TEMP:-${TMPDIR:-/tmp}}"
  if command -v cygpath >/dev/null 2>&1; then
    TMP_DIR_U="$(cygpath -u "$TMP_DIR_U")"
  fi
  TPZ_PATH="$TMP_DIR_U/$TPZ_NAME"
  if [ ! -f "$TPZ_PATH" ]; then
    TPZ_URL="https://github.com/godotengine/godot/releases/download/${TAG_VER}/${TPZ_NAME}"
    echo "[build_web] Baixando $TPZ_URL..."
    curl -fL --retry 3 -o "$TPZ_PATH" "$TPZ_URL"
  else
    echo "[build_web] Usando .tpz em cache: $TPZ_PATH"
  fi
  echo "[build_web] Extraindo templates..."
  if command -v unzip >/dev/null 2>&1; then
    unzip -qo -j "$TPZ_PATH" "templates/*" -d "$TPL_DIR"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c "import zipfile,os,shutil; z=zipfile.ZipFile('$TPZ_PATH'); [open(os.path.join('$TPL_DIR', os.path.basename(m)), 'wb').write(z.read(m)) for m in z.namelist() if m.startswith('templates/') and not m.endswith('/')]"
  elif command -v powershell.exe >/dev/null 2>&1; then
    WIN_TPZ="$(cygpath -w "$TPZ_PATH")"
    WIN_TPL="$(cygpath -w "$TPL_DIR")"
    powershell.exe -NoProfile -Command "Add-Type -AssemblyName System.IO.Compression.FileSystem; \$z=[System.IO.Compression.ZipFile]::OpenRead('$WIN_TPZ'); foreach(\$e in \$z.Entries){ if(\$e.FullName.StartsWith('templates/') -and \$e.Name -ne ''){ [System.IO.Compression.ZipFileExtensions]::ExtractToFile(\$e, (Join-Path '$WIN_TPL' \$e.Name), \$true) } }; \$z.Dispose()"
  else
    echo "ERRO: Nenhum extrator zip disponivel (unzip/python3/powershell)." >&2
    exit 1
  fi
fi

OUT_DIR="$ROOT_DIR/site/public/game"
mkdir -p "$OUT_DIR"

# Clean previous hashed outputs before export
rm -f "$OUT_DIR"/ifsul*.js "$OUT_DIR"/ifsul*.wasm "$OUT_DIR"/ifsul*.pck "$OUT_DIR"/ifsul*.html \
      "$OUT_DIR"/ifsul*.br "$OUT_DIR"/ifsul*.gz "$OUT_DIR"/ifsul*.png "$OUT_DIR"/ifsul*.svg "$OUT_DIR"/ifsul*.audio.worklet.js

echo "[build_web] Exportando preset Web (single-thread, Compatibility)..."
"$GODOT_BIN" --headless --path "$ROOT_DIR" --export-release "Web" "$OUT_DIR/ifsul.html"

echo "[build_web] Auditando .pck, gerando hash de versao e pre-comprimindo (br + gz)..."
node - <<'EOF'
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const zlib = require('zlib');

const outDir = path.resolve('site/public/game');
const jsRaw = path.join(outDir, 'ifsul.js');
const wasmRaw = path.join(outDir, 'ifsul.wasm');
const pckRaw = path.join(outDir, 'ifsul.pck');

for (const f of [jsRaw, wasmRaw, pckRaw]) {
  if (!fs.existsSync(f)) {
    throw new Error(`Arquivo esperado ausente apos export: ${f}`);
  }
}

// Verify forbidden folders are NOT packed inside ifsul.pck
const pckBuf = fs.readFileSync(pckRaw);
const forbidden = ['assets/ref/', 'shots/', 'docs/', 'tools/', 'site/'];
for (const pat of forbidden) {
  if (pckBuf.includes(Buffer.from(pat))) {
    throw new Error(`PROIBIDO: diretorio "${pat}" vazou para dentro de ifsul.pck!`);
  }
}

// Remove Godot's generated HTML/icons so only our custom shell is served
for (const extra of fs.readdirSync(outDir)) {
  if (extra.endsWith('.html') || extra.endsWith('.png') || extra.endsWith('.svg')) {
    fs.unlinkSync(path.join(outDir, extra));
  }
}

// Compute 8-char content hash across js + wasm + pck
const hasher = crypto.createHash('sha256');
hasher.update(fs.readFileSync(jsRaw));
hasher.update(fs.readFileSync(wasmRaw));
hasher.update(pckBuf);
const hash = hasher.digest('hex').slice(0, 8);

const base = `ifsul.${hash}`;
const files = {
  js: `${base}.js`,
  wasm: `${base}.wasm`,
  pck: `${base}.pck`
};

fs.renameSync(jsRaw, path.join(outDir, files.js));
fs.renameSync(wasmRaw, path.join(outDir, files.wasm));
fs.renameSync(pckRaw, path.join(outDir, files.pck));

const compressList = [files.js, files.wasm, files.pck];
for (const wk of ['audio.worklet.js', 'audio.position.worklet.js']) {
  const srcWk = path.join(outDir, `ifsul.${wk}`);
  if (fs.existsSync(srcWk)) {
    const dstWk = `${base}.${wk}`;
    fs.renameSync(srcWk, path.join(outDir, dstWk));
    compressList.push(dstWk);
  }
}

const sizes = {};
for (const fname of compressList) {
  const full = path.join(outDir, fname);
  const data = fs.readFileSync(full);
  if (fname === files.js) sizes.js = data.length;
  else if (fname === files.wasm) sizes.wasm = data.length;
  else if (fname === files.pck) sizes.pck = data.length;

  const br = zlib.brotliCompressSync(data, {
    params: {
      [zlib.constants.BROTLI_PARAM_QUALITY]: 9,
      [zlib.constants.BROTLI_PARAM_SIZE_HINT]: data.length
    }
  });
  fs.writeFileSync(`${full}.br`, br);

  const gz = zlib.gzipSync(data, { level: 9 });
  fs.writeFileSync(`${full}.gz`, gz);
}
sizes.total = sizes.js + sizes.wasm + sizes.pck;

const meta = {
  hash,
  version: hash,
  builtAt: new Date().toISOString(),
  executable: `/game/${base}`,
  mainPack: `/game/${files.pck}`,
  files,
  sizes
};
fs.writeFileSync(path.join(outDir, 'build-meta.json'), JSON.stringify(meta, null, 2) + '\n');
console.log(`[build_web] OK hash=${hash} wasm=${(sizes.wasm/1048576).toFixed(2)}MB pck=${(sizes.pck/1048576).toFixed(2)}MB js=${(sizes.js/1024).toFixed(1)}KB`);
EOF
