# Log de Iterações Visuais — IFSul Câmpus Sapucaia do Sul

| Ciclo | Shots avaliados | Defeito principal | Correção aplicada | Antes → Depois (frametime) | Status |
|---|---|---|---|---|---|
| 01 | 01–09 (iter-00/01) | Tetos/pátios invisíveis (backface culling), fachadas invertidas para dentro, `Label3D` espelhada, paredes escuras e fade no spawn | Corrigido winding CW em `_extrude_polygon_mesh`, normal externa das fachadas, reboco claro/terracota, totem sem double-sided e kill do fade na captura | 6.97ms → 7.58ms (01/03/04/08 revelaram telhados, pátio, janelas, frisos #2F9E41 e placa IFSul) | keep |
| 02 | 01, 02, 04, 09 | Neblina aérea lavada (02), céu procedural plano e noite quase preta (09) | Céu HDRI CC0 `sky_1k.hdr`, névoa 0.00028, SSAO/glow, sol dourado 190m e janelas emissivas + refletores noturnos | 7.58ms → 7.84ms (céu realista, sombras nítidas, janelas acesas e quadras iluminadas à noite) | keep |
