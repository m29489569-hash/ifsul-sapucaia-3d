# Diretrizes do Projeto — IFSul Sapucaia 3D (Roblox)

Este repositório é **100% focado em Roblox Studio (Luau)** e foi estruturado para manutenção autônoma e segura por agentes de IA via **Roblox Studio MCP** (e/ou Rojo).

---

## 1. Arquitetura e Mapa do Repositório

```text
ifsul-sapucaia-3d/
├── default.project.json            # Manifesto padrão Rojo (contrato src/ -> DataModel)
├── AGENTS.md                       # Este guia operacional para agentes de IA
├── README.md                       # Documentação principal do projeto
├── data/                           # Fonte única de verdade (métrico 1:1 em metros)
│   ├── campus.json                 # Polígonos georreferenciados (OSM), 16 blocos, quadras, 8 POIs
│   ├── interiors.json              # 92 salas/ambientes, 10 setores, pátios e placas
│   ├── shots.json                  # Câmeras padronizadas para regressão visual (metros)
│   ├── campus_geometry.zst.b64     # Snapshot binário SoA+Zstd+Base64 (10.565 Parts, 112 Signs, 34 Lights)
│   └── city/<cidade>/              # Tiles binários IFC2 (500 m, Zstd+Base64) e index.json da região
├── src/                            # Código-fonte Luau (strict)
│   ├── shared/                     # -> ReplicatedStorage.IFSul
│   │   ├── Config.luau             # Constantes métricas, cores institucionais, iluminação
│   │   ├── CityStyle.luau          # Raios de streaming, materiais e categorias da malha urbana
│   │   └── CampusData.luau         # GERADO por tools/sync_campus_data.py (não editar à mão)
│   ├── server/                     # -> ServerScriptService.IFSul
│   │   ├── CampusBuilder.luau      # Decodificador/construtor do mapa a partir de campus_geometry.zst.b64
│   │   ├── CityTileCodec.luau      # Decodificador IFC2 por tile de 500 m em lotes sem travar o Studio
│   │   ├── CityLoader.server.luau  # Carrega/descarrega tiles por raio a partir de ServerStorage.IFSulCity
│   │   └── CampusServer.server.luau# Dia/Noite e teleporte validado no servidor
│   └── client/                     # -> StarterPlayer.StarterPlayerScripts.IFSul
│       └── CampusHUD.client.luau   # HUD institucional, sala atual, Buscador [G] e Dia/Noite [N]
├── tools/                          # Utilitários Python de manutenção
│   ├── sync_campus_data.py         # Sincroniza data/*.json -> src/shared/CampusData.luau
│   ├── generate_planta_baixa.py    # Gera planta-baixa técnica cotada (SVG/PNG)
│   └── city/                       # Pipeline Overture Maps -> tiles IFC2 (build_city.py, cities.json)
├── assets/ref/                     # Referências oficiais (somente consulta)
│   ├── fotos_atuais/               # 7 fotos presenciais mais atuais do câmpus (19/11/2026)
│   ├── plantas_e_mapas/            # Mapa oficial das salas (DEPEN), ortofoto e OSM
│   └── INDEX_REFERENCIAS.md        # Catálogo detalhado de todas as referências
└── docs/                           # Screenshots do Roblox Studio, backlog, créditos e referências
```

---

## 2. Contrato de Escala e Hierarquia no Roblox Studio

- **Escala oficial 1:1:** `1 stud = 0,28 metros` (`STUDS_PER_METER = 1 / 0.28 ≈ 3.57142857`).
  - Sempre converta coordenadas de `data/*.json` (em metros) multiplicando por `STUDS_PER_METER`.
  - Sistema de coordenadas: mão direita, eixo **Y para cima** (`+X` Leste, `+Z` Sul).
- **Hierarquia do mapa em `Workspace.IFSul_Campus`:**
  - `Terrain` — terreno, Av. Copacabana, calçadas, estacionamentos, quadras e praças
  - `Buildings` — 16 edificações, telhados, claraboias, janelas e fachadas (portas abertas caminháveis)
  - `Interiors` — pisos internos, divisórias e mobiliário das 92 salas
  - `Props` — árvores (ipês, araucárias), carros, postes, bancos, muros e portões
  - `Signage` — placas `SurfaceGui` (`CanCollide = false`)
  - `Lights` — iluminação `PointLight` (ativada no modo noturno)
  - `CampusSpawn` — `SpawnLocation` na portaria principal
- **Hierarquia da expansão urbana em `Workspace.IFSul_City` e `ServerStorage.IFSulCity`:**
  - `ServerStorage.IFSulCity.<cidade>` — `Index` (`StringValue` com `index.json`) e `Tiles` (`Folder` de `StringValue`s `.b64` no formato `IFC2`)
  - `Workspace.IFSul_City.<cidade>.<tx_tz>` — `Model` atômico por tile de 500 m com `Ground`, `Roads`, `Sidewalks` e `Buildings` gerenciados por `CityLoader.server.luau`

---

## 3. Fluxo de Trabalho com Roblox Studio MCP

1. **Identificar a instância:** sempre execute `list_roblox_studios` primeiro e confirme qual place está aberto antes de modificar o jogo.
2. **Sincronizar código (`src/` → Studio):**
   - `src/shared/*.luau` → `ModuleScript` em `ReplicatedStorage.IFSul`
   - `src/server/*.server.luau` → `Script` em `ServerScriptService.IFSul`
   - `src/server/*.luau` → `ModuleScript` em `ServerScriptService.IFSul`
   - `src/client/*.client.luau` → `LocalScript` em `StarterPlayer.StarterPlayerScripts.IFSul`
3. **Operações pesadas em `execute_luau`:** ao criar/modificar centenas ou milhares de instâncias, processe em lotes de **~500 itens** com `task.wait()` entre lotes para nunca congelar o Studio nem derrubar a conexão MCP.
4. **Reconstrução do mapa:** para reconstruir o câmpus inteiro em um place vazio, use `CampusBuilder.BuildFromBase64(...)` com o conteúdo de `data/campus_geometry.zst.b64`.
5. **Validação obrigatória antes de encerrar:**
   - Use `screen_capture` (convertendo posições de `data/shots.json` via `× 3.5714`) para conferir visualmente mudanças de cena/UI.
   - Use `start_stop_play` + `get_console_output` para confirmar **zero erros de runtime** em Luau (e pare o Play ao terminar).

---

## 4. Pipeline de Dados

- Sempre que alterar `data/campus.json` ou `data/interiors.json`, execute:
  ```bash
  python tools/sync_campus_data.py
  ```
- Nunca edite `src/shared/CampusData.luau` manualmente — ele é sempre regerado pelo script acima.
- Para gerar ou atualizar ruas e edifícios de uma cidade/região a partir do Overture Maps (em cache em `data/cache/`), execute:
  ```bash
  python -m tools.city.build_city --city pilot --summary
  ```

---

## 5. Fluxo Git ao Finalizar Tarefas

- Sempre que concluir uma tarefa que envolva alterações no repositório (após validar os scripts/testes aplicáveis), faça o commit das mudanças e execute `git push` para enviar ao GitHub (`origin`), a menos que o usuário peça explicitamente para não enviar ou haja falhas impeditivas.
- Antes de concluir a resposta final, confirme se não ficaram commits locais pendentes de push.
