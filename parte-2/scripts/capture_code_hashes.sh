#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PART2_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
PROJECT_DIR="$(cd -- "${PART2_DIR}/.." && pwd)"
OUTPUT="${PROJECT_DIR}/evidencias/av2/brutas/code-sha256.txt"

if command -v sha256sum >/dev/null 2>&1; then
  hash_file() {
    sha256sum "$1" | awk '{print $1}'
  }
elif command -v shasum >/dev/null 2>&1; then
  hash_file() {
    shasum -a 256 "$1" | awk '{print $1}'
  }
else
  printf 'ERRO: sha256sum ou shasum é obrigatório.\n' >&2
  exit 2
fi

mkdir -p "$(dirname -- "$OUTPUT")"
manifest="$(mktemp)"
find "$PART2_DIR" "$PROJECT_DIR/consultas" "$PROJECT_DIR/verificacao" \
  -type f \
  \( -name '*.tf' -o -name '*.py' -o -name '*.sh' -o -name '*.sql' \) \
  -not -path '*/.terraform/*' \
  -not -path '*/.generated/*' \
  -not -path '*/.runtime/*' \
  -print | sort | while IFS= read -r file; do
    relative="${file#${PROJECT_DIR}/}"
    printf '%s  %s\n' "$(hash_file "$file")" "$relative"
  done >"$manifest"
mv "$manifest" "$OUTPUT"
printf '%s\n' "$OUTPUT"
