#!/usr/bin/env bash
set -euo pipefail
mkdir -p assets/{models,textures,audio,hdri,ref}

# Reference images (for proportions & palette only; not redistributed if restricted)
curl -fsSL "http://static.sapucaia.ifsul.edu.br/media/acervo/MSS-00.266.jpg" -o assets/ref/fachada_atual_MSS-00.266.jpg || true
curl -fsSL "http://static.sapucaia.ifsul.edu.br/media/acervo/MSS-00.2155.jpg" -o assets/ref/fachada_auditorio_mastros_MSS-00.2155.jpg || true
curl -fsSL "http://static.sapucaia.ifsul.edu.br/media/acervo/MSS-00.117.jpg" -o assets/ref/fachada_2006_MSS-00.117.jpg || true
curl -fsSL "http://static.sapucaia.ifsul.edu.br/media/acervo/MSS-00.572.jpg" -o assets/ref/fachada_uned_MSS-00.572.jpg || true
curl -fsSL "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/export?bbox=-51.1575,-29.8168,-51.1545,-29.8134&bboxSR=4326&size=1024,1024&f=image" -o assets/ref/satellite_esri_campus.jpg || true
curl -fsSL -A "GodotCampusBuilder/1.0" "https://tile.openstreetmap.org/17/46909/77026.png" -o assets/ref/osm_tile_campus.png || true

# Custom seamless campus textures in assets/textures/*_diff.jpg are tracked directly in git.
# CC0 Poly Haven HDRI (1K)
curl -fsSL "https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/1k/kloofendal_48d_partly_cloudy_puresky_1k.hdr" -o assets/hdri/sky_1k.hdr || true

echo "Fetch concluído. Fallbacks procedurais no engine garantem execução 100% offline."
