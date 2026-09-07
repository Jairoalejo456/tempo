#!/bin/bash
# Genera el juego completo de iconos de la app a partir de un PNG cuadrado de 1024×1024.
#
#   ./Tools/make-appicon.sh ruta/a/logo-1024.png
#
# Escribe los PNG dentro de Snapper/Resources/Assets.xcassets/AppIcon.appiconset
# y actualiza su Contents.json. Después basta con recompilar.

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Uso: $0 <logo-1024.png>" >&2
  exit 1
fi

SOURCE="$1"
if [ ! -f "$SOURCE" ]; then
  echo "No existe el archivo: $SOURCE" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SET="$ROOT/Snapper/Resources/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$SET"

# (tamaño en puntos, escala) -> píxeles
declare -a ENTRIES=("16 1" "16 2" "32 1" "32 2" "128 1" "128 2" "256 1" "256 2" "512 1" "512 2")

JSON_IMAGES=""
for entry in "${ENTRIES[@]}"; do
  set -- $entry
  POINTS=$1
  SCALE=$2
  PIXELS=$((POINTS * SCALE))
  NAME="icon_${POINTS}x${POINTS}"
  if [ "$SCALE" -eq 2 ]; then NAME="${NAME}@2x"; fi
  NAME="${NAME}.png"

  sips -s format png -z "$PIXELS" "$PIXELS" "$SOURCE" --out "$SET/$NAME" >/dev/null
  echo "  $NAME (${PIXELS}px)"

  JSON_IMAGES="${JSON_IMAGES}    {\n      \"filename\" : \"${NAME}\",\n      \"idiom\" : \"mac\",\n      \"scale\" : \"${SCALE}x\",\n      \"size\" : \"${POINTS}x${POINTS}\"\n    },\n"
done

JSON_IMAGES="${JSON_IMAGES%,\\n}"
printf "{\n  \"images\" : [\n${JSON_IMAGES}\n  ],\n  \"info\" : {\n    \"author\" : \"xcode\",\n    \"version\" : 1\n  }\n}\n" > "$SET/Contents.json"

echo ""
echo "Iconos generados en $SET"
echo "Recompila la app para verlos: xcodebuild -project Snapper.xcodeproj -scheme Snapper build"
