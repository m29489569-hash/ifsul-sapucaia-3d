# Log de Iterações Visuais — IFSul Câmpus Sapucaia do Sul

| Ciclo | Shots avaliados | Defeito principal | Correção aplicada | Antes → Depois (frametime) | Status |
|---|---|---|---|---|---|
| 01 | 01–09 (iter-00/01) | Tetos/pátios invisíveis (backface culling), fachadas invertidas para dentro, `Label3D` espelhada, paredes escuras e fade no spawn | Corrigido winding CW em `_extrude_polygon_mesh`, normal externa das fachadas, reboco claro/terracota, totem sem double-sided e kill do fade na captura | 6.97ms → 7.58ms (01/03/04/08 revelaram telhados, pátio, janelas, frisos #2F9E41 e placa IFSul) | keep |
