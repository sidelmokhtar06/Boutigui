#!/usr/bin/env bash
# Lancement local de MESK en mode économe en mémoire.
#
# Pourquoi ce script : `flutter run -d chrome` démarre SA PROPRE instance de
# Chrome en plus du compilateur Dart de développement. Sur une machine de
# 8 Go où Firefox et l'éditeur tournent déjà, ça suffit à saturer la RAM.
#
# Deux modes :
#
#   ./run_local.sh serve   (défaut) compile une fois, puis sert les fichiers
#                          statiques. Le compilateur s'arrête à la fin de la
#                          compilation : il ne reste qu'un serveur de
#                          quelques mégaoctets. Pas de rechargement à chaud.
#                          C'est le mode de la DÉMO.
#
#   ./run_local.sh dev     `flutter run -d web-server` : rechargement à chaud,
#                          mais SANS lancer un second navigateur — on ouvre
#                          l'adresse dans le Firefox déjà ouvert.
#
#   ./run_local.sh release compilation optimisée à fond, pour METTRE EN LIGNE.
#                          Demande ~3 Go : à ne pas lancer pendant qu'on
#                          travaille sur cette machine.
#
# Pourquoi `serve` ne compile PAS en `--release` (mesuré le 20 septembre
# 2026 sur cette machine) :
#
#     --release                              pic 3120 Mo   42 s   4,0 Mo de JS
#     -O1 --no-source-maps --no-wasm-dry-run pic 1202 Mo   32 s   4,2 Mo de JS
#
# 1,9 Go de moins pour 200 ko de JavaScript en plus. Sur 7,5 Go de RAM avec
# un navigateur et un éditeur déjà ouverts, le pic à 3 Go fait basculer la
# machine dans le swap — c'est ça qu'on voyait monter à 99 %.
#
# `--no-wasm-dry-run` compte pour une bonne part : par défaut Flutter fait
# une compilation WebAssembly « à blanc » EN PLUS de la compilation
# JavaScript, uniquement pour signaler d'éventuels avertissements.
#
# Les clés viennent de .env.local (non versionné), pour ne pas retaper deux
# `--dart-define` de 100 caractères à chaque lancement.

set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -f .env.local ]]; then
  cat >&2 <<'MSG'
.env.local manquant. Créez-le à côté de ce script :

    SUPABASE_URL=https://votre-projet.supabase.co
    SUPABASE_ANON_KEY=votre-cle-anon

La clé "anon" est publique par conception. Ne mettez JAMAIS la clé
"service_role" dans ce fichier : elle contourne toutes les règles RLS.
MSG
  exit 1
fi

set -a; source .env.local; set +a

: "${SUPABASE_URL:?SUPABASE_URL absent de .env.local}"
: "${SUPABASE_ANON_KEY:?SUPABASE_ANON_KEY absent de .env.local}"

DEFINES=(
  --dart-define=SUPABASE_URL="$SUPABASE_URL"
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
)
[[ -n "${R2_PUBLIC_BASE_URL:-}" ]] && DEFINES+=(
  --dart-define=USE_R2=true
  --dart-define=R2_PUBLIC_BASE_URL="$R2_PUBLIC_BASE_URL"
)

PORT="${PORT:-8080}"

case "${1:-serve}" in
  serve)
    echo "Compilation (une fois, profil léger)…"
    # Plafond de tas pour le compilateur (21 septembre 2026). Sans lui,
    # dart2js grossit jusqu'à ce qu'il y ait de la place — et quand il n'y
    # en a pas, c'est le noyau qui tue le processus (code 137), parfois en
    # emportant autre chose. Avec le plafond, il passe plus de temps à
    # ramasser ses miettes et tient dans moins d'un gigaoctet : la
    # compilation est plus lente (environ 90 s au lieu de 30) mais elle
    # aboutit même avec un navigateur et un éditeur déjà ouverts.
    DART_VM_OPTIONS="--old_gen_heap_size=700" \
      flutter build web -O1 --no-source-maps --no-wasm-dry-run "${DEFINES[@]}"
    echo
    echo "  http://localhost:$PORT"
    echo "  Ctrl+C pour arrêter."
    echo
    # Le serveur de la bibliothèque standard Python : aucune dépendance à
    # installer, et une empreinte mémoire de l'ordre de 10 Mo.
    exec python3 -m http.server "$PORT" --directory build/web --bind 127.0.0.1
    ;;
  dev)
    echo "Rechargement à chaud. Ouvrez l'adresse affichée dans Firefox."
    exec flutter run -d web-server --web-port "$PORT" "${DEFINES[@]}"
    ;;
  release)
    # Pour la mise en ligne seulement. Fermez le navigateur et l'éditeur
    # avant, sinon la machine passe en swap pendant la compilation.
    flutter build web --release "${DEFINES[@]}"
    echo "Prêt dans build/web/"
    ;;
  *)
    echo "Usage: $0 [serve|dev|release]" >&2
    exit 1
    ;;
esac
