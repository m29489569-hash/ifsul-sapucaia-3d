# IFSul — Câmpus Sapucaia do Sul 3D
Execute `godot --path .` (Godot 4.x) para abrir diretamente no câmpus jogável.
**Controles:** `WASD` mover | `Shift` correr | `Espaço` pular | `Mouse` olhar | `E` examinar POI
`F` alternar câmera drone (scroll = zoom, Espaço/Ctrl = subir/descer) | `N` dia/noite | `M` mudo | `Esc` pausa
Opcional (offline já incluído): execute `bash tools/fetch_assets.sh` para baixar texturas CC0 e referências.

## Deploy Web (Render.com)
1. Gere/atualize o export web: `bash tools/build_web.sh` e teste local com `npm start` (`http://localhost:3000`).
2. Faça push deste repositório para o GitHub (com `site/public/game/` commitado).
3. No Render.com, clique em **New Blueprint**, conecte o repositório e confirme o deploy (`render.yaml`).
4. O plano free hiberna após inatividade; a tela de carregamento cobre o *cold start* inicial.
