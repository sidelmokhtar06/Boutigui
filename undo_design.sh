#!/usr/bin/env bash
# Annule les retouches de design du 20 septembre 2026.
#
# Chaque fichier modifié a été copié tel quel dans .design-backup-<horodatage>/
# AVANT toute modification. Ce script les remet en place.
#
#   ./undo_design.sh          restaure la dernière sauvegarde
#   ./undo_design.sh --list   montre les sauvegardes disponibles
#   ./undo_design.sh <horodatage>  restaure celle-là
set -euo pipefail
cd "$(dirname "$0")"

if [[ "${1:-}" == "--list" ]]; then
  ls -d .design-backup-*/ 2>/dev/null | sed 's|^\.design-backup-||; s|/$||' || echo "aucune sauvegarde"
  exit 0
fi

TS="${1:-$(cat .design-backup-latest 2>/dev/null || true)}"
[[ -z "$TS" ]] && { echo "Aucune sauvegarde trouvée. ./undo_design.sh --list" >&2; exit 1; }
BK=".design-backup-$TS"
[[ -d "$BK" ]] || { echo "Sauvegarde introuvable : $BK" >&2; exit 1; }

echo "Restauration depuis $BK :"
# `cd "$BK"` dans un sous-shell pour lister les chemins relatifs, puis on
# recopie chacun par-dessus l'original.
while IFS= read -r f; do
  cp "$BK/$f" "$f"
  echo "  $f"
done < <(cd "$BK" && find . -type f | sed 's|^\./||')

echo
echo "Fait. Relancez ./run_local.sh serve pour recompiler."
