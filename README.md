<div align="center">

# 🏛️ IFSul — Câmpus Sapucaia do Sul 3D

**Gêmeo Digital e Exploração Interativa 3D em Escala Métrica 1:1**  
*Instituto Federal de Educação, Ciência e Tecnologia Sul-rio-grandense (RS)*

[![Godot Engine](https://img.shields.io/badge/Godot_Engine-4.x-478CBF?logo=godotengine&logoColor=white)](https://godotengine.org/)
[![WebGL 2.0](https://img.shields.io/badge/Web-WebGL_2.0_%2B_Wasm-2F9E41?logo=webgl&logoColor=white)](#como-executar)
[![Node.js](https://img.shields.io/badge/Server-Node.js_%2B_Express-339933?logo=nodedotjs&logoColor=white)](site/server.js)
[![OpenStreetMap](https://img.shields.io/badge/Geodata-OpenStreetMap_1%3A1-7EBC6F?logo=openstreetmap&logoColor=white)](https://www.openstreetmap.org/way/333342533)
[![License: MIT](https://img.shields.io/badge/License-MIT_%2F_CC0-blue.svg)](LICENSE)

[Visão Geral](#-visão-geral) •
[Galeria](#-galeria-visual) •
[Tour Guiado (POIs)](#-tour-guiado--8-pontos-de-interesse) •
[Controles](#-controles) •
[Como Executar](#-como-executar) •
[Arquitetura](#-arquitetura-e-destaques-técnicos) •
[Estrutura](#-estrutura-do-repositório) •
[Créditos](#-documentação-e-créditos)

</div>

---

![Visão de Spawn e HUD no Câmpus 3D](docs/screenshots/01_spawn_hud.png)

## 📖 Visão Geral

**IFSul — Câmpus Sapucaia do Sul 3D** é uma reconstrução tridimensional interativa e georreferenciada do primeiro câmpus do Instituto Federal Sul-rio-grandense estabelecido fora de Pelotas (inaugurado em 1996 na **Av. Copacabana, 100 — Bairro Piratini, Sapucaia do Sul/RS**).

O ambiente virtual reconstrói os **38.600 m²** do terreno (~16.000 m² de área construída) em **escala métrica real (1:1)** a partir de polígonos cartográficos do **OpenStreetMap (`way/333342533`)**, **ortofoto aérea Zoom-19** e do **Mapa Oficial das Salas (DEPEN Sapucaia)**, incluindo interiores navegáveis a pé por todos os setores (`Setores 100–500`, `Bloco 800`, `Biblioteca`, `Sede Social` e `Educação Física`). O projeto pode ser executado tanto nativamente no desktop via **Godot Engine 4** quanto diretamente no navegador via **WebAssembly / WebGL 2.0**.

### Principais Recursos

- 🗺️ **Implantação Georreferenciada 1:1:** 16 edificações reais em proporção térrea fiel, conexões cobertas, guarita, caixa d'água cilíndrica, complexo esportivo com 3 quadras, horta experimental, estacionamentos, lago dos patos, topiaria institucional e malha viária do entorno (Av. Copacabana em pista dupla com canteiro central vegetado).
- 🚪 **Interiores Navegáveis e Buscador de Salas (`[G]` / `[Tab]`):** Explore a pé **92 salas e ambientes internos** mobiliados em `MultiMesh`, com placas de porta oficiais, indicador de sala atual no HUD, minimapa colorido por setor com zoom indoor automático, mapa expandido (`[Tab]`), busca por número, nome ou apelido antigo (`[G]`) e modo Raio-X de telhados (`[T]`) na câmera Drone.
- 🎓 **Tour Guiado Interativo (8/8 POIs):** Marcos históricos, administrativos, acadêmicos, laboratoriais, estudantis e esportivos com painéis informativos e rastreamento de progresso no HUD e minimapa.
- 🚁 **Modo A Pé (FPS) e Câmera Drone:** Alterne livremente entre a caminhada em primeira pessoa com áudio espacial de passos/ambiente e o sobrevoo panorâmico do câmpus.
- 🌗 **Ciclo Dia e Noite Dinâmico:** Iluminação diurna com HDRI 1K CC0, SSAO e sombras direcionais nítidas, além de modo noturno com janelas emissivas e refletores nas quadras, fachada, interiores e jardins.
- 🌐 **Shell Web de Alta Performance:** Interface web customizada inspirada na sinalização arquitetônica da Rede Federal, com barra de progresso real, pré-compressão **Brotli (`.br`)** e **Gzip (`.gz`)**, seleção de qualidade gráfica e suporte a deploy imediato no **Render.com**.

---

## 📸 Galeria Visual

| Fachada Principal e Auditório Pedro Kaizer | Portaria Principal (Av. Copacabana, 100) |
| :---: | :---: |
| ![Fachada Principal e Auditório](docs/screenshots/04_main_facade.png) | ![Portaria Principal](docs/screenshots/03_entrance_guarita.png) |
| **Vista Aérea Diurna (Implantação 1:1)** | **Vista Aérea Noturna (Iluminação Emissiva)** |
| ![Vista Aérea Diurna](docs/screenshots/02_aerial_overview.png) | ![Vista Aérea Noturna](docs/screenshots/09_aerial_night.png) |
| **Pátio Central e Blocos Acadêmicos** | **Complexo Esportivo e Quadra Poliesportiva** |
| ![Pátio Central](docs/screenshots/05_central_courtyard.png) | ![Quadras Esportivas](docs/screenshots/06_sports_courts.png) |
| **Interface Web (Placa Institucional de Entrada)** | **Planta-Baixa Técnica Cotada (Escala 1:1)** |
| ![Interface Web](docs/screenshots/10_web_overlay.png) | ![Planta Baixa Técnica](assets/ref/plantas_e_mapas/planta_baixa_tecnica_cotada.png) |

---

## 📍 Tour Guiado — 8 Pontos de Interesse

Durante a exploração, aproxime-se dos marcos sinalizados no câmpus (e destacados no minimapa) e pressione **`E`** para inspecionar cada ponto:

| # | Ponto de Interesse (POI) | Localização no Câmpus | Destaque Institucional |
| :-: | :--- | :--- | :--- |
| **1** | **Portaria Principal e Histórico (1996)** | Acesso Oeste (`Av. Copacabana`) | Fundação como UNED da ETF-Pelotas (1996), transição para CEFET-RS (1999) e IFSul (2008). |
| **2** | **Setor 100 (Administração/Saúde) e Auditório 504** | Eixo Frontal Sudoeste (`B2`/`B3`/`B5`) | Direção-Geral (`115`), Ensino (`105`), Saúde (`112`), Psicologia (`106`), Convivência (`119`) e Auditório `504` (300 lugares). |
| **3** | **Setor 200 — Ensino, CORAC, Miniauditório 201 e Cantina** | Eixo Central e Leste (`B4`/`B6`) | Recepção, Miniauditório `201`, CORAC, salas `204–229`, Labs 1–6, Cantina, Eventos (`231`), Depep (`233`) e Lab de Inovação (`234`). |
| **4** | **Setor 300 — Plásticos, Química (304) e Modular 309** | Pavilhão Nordeste (`B7`/`B10`) | Lab de Plásticos, LCQ (`303`), Lab de Química (`304`), Reciclagem (`305`), Bio (`307`), Antiga Sala 8 (`308`) e Modular (`309`). |
| **5** | **Setor 400 — Engenharia Mecânica, CNC (401) e DIMP (405)** | Pavilhão Sudeste (`B12`) | Lab de Mecânica, Manutenção, Lab CNC (`401`), Lab 7 (`402`), Desenho / Antiga 14 (`403`) e DIMP (`405`). |
| **6** | **Bloco 800 (Salas 801–812, DA/Grêmio 807) e Horta** | Quadrante Nordeste (`B11`) | Edificação em cruz junto à Horta experimental com salas `801–812` (`P01–P10`), Lab. Física (`804`) e DA / Grêmio Estudantil (`807`). |
| **7** | **Biblioteca do Câmpus e Lago dos Patos** | Setor Sul (`B15` / `B16`) | Prédio em cruz no setor sul (>580 m²) após o Lago dos Patos, acessado pela alameda em Y junto à Sede Social. |
| **8** | **Complexo Esportivo e Educação Física** | Setor Noroeste (`B14`) | Educação Física (academia/vestiários), Quadra Poliesportiva Coberta azul, Quadra de Vôlei de areia e quadra poliesportiva externa. |

---

## 🎮 Controles

| Tecla / Entrada | Ação |
| :--- | :--- |
| `W` `A` `S` `D` ou `Setas` | Movimentar pelo câmpus e interiores |
| `Mouse` | Olhar ao redor (rotação de câmera) |
| `Shift` | Correr (sprint) |
| `Espaço` | Pular (modo a pé) / Subir (modo drone) |
| `Ctrl` | Descer (modo drone) |
| `Scroll do Mouse` | Ajustar zoom / velocidade no modo drone |
| `E` | Examinar Ponto de Interesse (POI) próximo |
| `G` | Abrir **Buscador de Salas** (busca por número, nome ou código antigo) |
| `Tab` | Alternar **Mapa Expandido** colorido por setores e salas |
| `F` | Alternar entre **Modo A Pé (FPS)** e **Câmera Drone** |
| `T` | Alternar corte de telhados (**Raio-X de interiores**, no modo Drone) |
| `N` | Alternar ciclo **Dia / Noite** |
| `M` | Ativar / Desativar som ambiente e efeitos |
| `Esc` | Abrir menu de pausa / fechar modais / liberar cursor |

---

## 🚀 Como Executar

### 1. Executar no Navegador (Servidor Web Local)

O repositório já inclui o pacote WebGL2 pré-compilado e comprimido em `site/public/game/`. Para iniciar o servidor Express localmente:

```bash
# Instalar dependências (Node.js 18+)
npm install

# Iniciar o servidor em http://localhost:3000
npm start
```

Abra **`http://localhost:3000`** em qualquer navegador moderno com suporte a WebGL 2.0.

### 2. Executar Nativamente no Godot Engine (Desktop)

Requer **Godot Engine 4.x** (testado na versão `4.7-stable`):

```bash
# Abrir diretamente o câmpus jogável
godot --path .

# Ou abrir o projeto no editor da Godot
godot --editor --path .
```

### 3. Build Web, Captura e Testes Automatizados (QA)

```bash
# Recompilar o export Web (.wasm + .pck) e gerar pré-compressão Brotli/Gzip
npm run build:web

# Executar suíte E2E automatizada no navegador (Playwright)
npm run test:web

# Executar verificação de QA física/lógica headless no Godot
godot --headless --path . -s tools/qa_verify.gd
```

### 4. Deploy em Nuvem (Render.com)

O arquivo [`render.yaml`](render.yaml) configura o deploy contínuo via **Render Blueprint**:
1. Conecte este repositório no painel do [Render.com](https://render.com) via **New Blueprint**.
2. O serviço utiliza `npm ci --omit=dev` no build, `node site/server.js` na inicialização e monitoramento automático na rota `/healthz`.

---

## 🏗️ Arquitetura e Destaques Técnicos

- **Geração Procedural Baseada em Dados (`scripts/campus_builder.gd` & `scripts/interior_builder.gd`):** Lê as coordenadas métricas de [`data/campus.json`](data/campus.json) e o catálogo de 92 ambientes de [`data/interiors.json`](data/interiors.json), construindo shells externos vazados com portais reais de entrada, divisórias internas, placas de porta, sinalização suspensa e mobiliário completo em `MultiMeshInstance3D` com culling por proximidade de setor.
- **Instanciação por Hardware (`MultiMeshInstance3D`):** Árvores multi-camada (incluindo Araucárias típicas do sul), hortaliças, mobília de salas e laboratórios, veículos em 3 partes nos estacionamentos, postes de iluminação e residências do bairro vizinho são agrupados em `MultiMesh` para manter alta taxa de quadros no Desktop e WebGL2.
- **Materiais PBR + Fallbacks Procedurais (`scripts/materials.gd`):** Utiliza texturas PBR CC0 (asfalto, concreto, grama, piso cerâmico e metal) combinadas com geração procedural em código da marca oficial do IFSul e sinalizações, garantindo funcionamento **100% offline**.
- **Servidor Web Otimizado (`site/server.js`):** Serve assets versionados por hash SHA-256 (`ifsul.<hash>.wasm`, `.pck`, `.js`) com cabeçalhos `Cache-Control: immutable` e entrega diretamente os binários `.br` (Brotli) ou `.gz` (Gzip) negociados via `Accept-Encoding`.

---

## 📂 Estrutura do Repositório

```text
ifsul-sapucaia-3d/
├── assets/
│   ├── audio/                  # Áudio espacial procedural (vento, pássaros, passos)
│   ├── hdri/                   # Skybox HDRI 1K CC0 (Poly Haven)
│   ├── textures/               # Texturas PBR 1K CC0 (asfalto, concreto, grama, piso, metal)
│   └── ref/                    # Mapa oficial das salas, ortofoto Zoom-19 e plantas-baixas 1:1
├── data/
│   ├── campus.json             # Polígonos georreferenciados (OSM), 16 blocos, 3 quadras, horta e 8 POIs
│   ├── interiors.json          # Catálogo espacial de 92 salas/ambientes, jardins internos e placas
│   └── shots.json              # Câmeras padronizadas (exterior + interior) para regressão visual
├── docs/
│   ├── screenshots/            # Capturas de tela em alta definição do projeto
│   ├── BACKLOG.md              # Histórico de prioridades e melhorias de fidelidade
│   ├── CREDITS.md              # Créditos detalhados e licenças de todos os recursos
│   ├── ITERATIONS.md           # Log de evolução visual e métricas
│   └── REFERENCES.md           # Fontes institucionais e cartográficas atuais
├── scenes/
│   ├── main.tscn               # Cena principal 3D do câmpus
│   ├── player.tscn             # Controlador FPS + Câmera Drone
│   └── hud.tscn                # Interface de usuário, buscador de salas, modais e minimapa
├── scripts/
│   ├── campus_builder.gd       # Construtor procedural 3D do câmpus, shells vazados e entorno
│   ├── interior_builder.gd     # Construtor modular de divisórias, mobiliário MultiMesh e busca
│   ├── main.gd                 # Ciclo dia/noite, áudio, estado do tour, busca e ponte JS/Web
│   ├── materials.gd            # Materiais PBR, shaders e geração vetorial de placas/logos
│   ├── perf_manager.gd         # Gerenciamento de LOD, culling por setor e orçamento de luzes
│   ├── player.gd               # Física de movimentação a pé e voo livre (drone)
│   ├── hud.gd                  # HUD, pill de sala atual, buscador [G] e mapa expandido [Tab]
│   └── minimap.gd              # Mapa 2D por setores com zoom indoor automático
├── site/
│   ├── server.js               # Servidor Express com suporte a Brotli/Gzip e /healthz
│   └── public/                 # Shell HTML5/CSS3, fontes OFL e pacote WebGL2 compilado
├── tools/
│   ├── build_web.sh            # Pipeline de exportação Web + auditoria .pck + compressão
│   ├── web_smoke.mjs           # Testes E2E automatizados com Playwright
│   ├── qa_verify.gd            # Suite de testes funcionais, interiores e colisão no Godot
│   ├── capture.gd / capture.sh # Automação de capturas e benchmark de frametime
│   ├── generate_planta_baixa.py# Gerador da planta-baixa técnica cotada (SVG/PNG)
│   └── fetch_assets.sh         # Script reprodutível para download de texturas CC0
├── export_presets.cfg          # Configuração de exportação Web (Godot 4)
├── project.godot               # Configuração principal do projeto Godot 4
├── package.json                # Scripts NPM e dependências do servidor/testes web
├── render.yaml                 # Blueprint de deploy para Render.com
└── LICENSE                     # Licença MIT (código) e notas de licenciamento de assets
```

---

## 📚 Documentação e Créditos

- **[Créditos e Licenças dos Assets (`docs/CREDITS.md`)](docs/CREDITS.md):** Relação completa de texturas PBR e HDRI (Poly Haven — **CC0 1.0**), dados geoespaciais (OpenStreetMap — **ODbL 1.0**), fontes tipográficas (Archivo Black e Inter — **SIL OFL 1.1**) e identidade visual institucional.
- **[Referências Oficiais e Cartográficas (`docs/REFERENCES.md`)](docs/REFERENCES.md):** Referências do Mapa Oficial das Salas (DEPEN Sapucaia), OpenStreetMap e ortofoto Esri Zoom-19.
- **[Índice do Acervo de Referências (`assets/ref/INDEX_REFERENCIAS.md`)](assets/ref/INDEX_REFERENCIAS.md):** Catálogo do Mapa das Salas, ortofoto, OSM e plantas-baixas técnicas cotadas.
- **[Log de Iterações Visuais (`docs/ITERATIONS.md`)](docs/ITERATIONS.md):** Registro técnico das iterações de fidelidade arquitetônica e desempenho.

---

## 📄 Licença

O código-fonte deste projeto é distribuído sob a licença **[MIT](LICENSE)**.  
Os recursos gráficos, sonoros, tipográficos e geoespaciais seguem suas respectivas licenças abertas (**CC0 1.0**, **ODbL 1.0** e **SIL OFL 1.1**), conforme detalhado em [`docs/CREDITS.md`](docs/CREDITS.md).
