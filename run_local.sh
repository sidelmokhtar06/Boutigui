#!/usr/bin/env bash
# Lancement local de Boutigui en mode économe en mémoire.
#
# Pourquoi ce script : `flutter run -d chrome` démarre SA PROPRE instance de
# Chrome en plus du compilateur Dart de développement. Sur une machine de
# 8 Go où Firefox et l'éditeur tournent déjà, ça suffit à saturer la RAM.
#
# ---------------------------------------------------------------------
# MESURES DU 21 SEPTEMBRE 2026 — Flutter 3.47.4, sur cette machine
# ---------------------------------------------------------------------
#
# Les chiffres qui figuraient ici avant venaient de Flutter 3.27 et ne
# tiennent PLUS. Remesurés, pic de RSS de l'ensemble des processus Dart :
#
#     mode      compilateur   pic RSS   ensuite            rechargement
#     --------  ------------  --------  -----------------  ------------
#     serve     dart2js -O1   1830 Mo   ~10 Mo (python)    non
#     dev       DDC           1330 Mo   1320 Mo (résident) OUI
#
# Deux conclusions, contraires à ce que disait la version précédente :
#
#  1. `dev` a le pic le PLUS BAS des deux (1,3 Go contre 1,8 Go). On le
#     croyait plus lourd parce qu'il reste résident — mais c'est
#     justement ce qui évite de repayer le pic à chaque modification.
#     Pour TRAVAILLER, c'est le bon mode. `serve` ne garde l'avantage que
#     pour laisser tourner la démo sans rien qui consomme.
#
#  2. `DART_VM_OPTIONS=--old_gen_heap_size=700` NE MARCHAIT PAS. Ce
#     réglage ne plafonne que le tas « vieille génération » de Dart, pas
#     la mémoire totale du processus : le RSS est monté à 1830 Mo malgré
#     lui. En revanche il forçait le ramasse-miettes à tourner sans arrêt
#     — la compilation est passée de ~90 s à PLUS DE DOUZE MINUTES, en
#     saturant le swap. Il est retiré : c'était le pire des deux mondes.
#
# Ce qui protège vraiment la machine, c'est le plafond cgroup ci-dessous
# (`systemd-run --scope -p MemoryMax=`). Là où le réglage Dart demandait
# poliment, le noyau impose : si la compilation dépasse le plafond, c'est
# ELLE qui est arrêtée, jamais Firefox ni la session graphique. C'est la
# différence entre « la machine rame puis tue quelque chose au hasard »
# et « la compilation échoue avec un message clair ».
#
# ---------------------------------------------------------------------
# CE QUI COMPTE LE PLUS : CE QUI TOURNE DÉJÀ
# ---------------------------------------------------------------------
#
# Sur 7,5 Go, le bureau en consommait 6,3 au moment de la mesure —
# Firefox à lui seul 3,3 Go. Aucun réglage de compilation ne rattrape
# ça : il faut ~1,4 Go de libre pour `dev`, ~1,9 Go pour `serve`.
# `./run_local.sh check` le vérifie avant de lancer quoi que ce soit.
#
# Les clés viennent de .env.local (non versionné), pour ne pas retaper
# deux `--dart-define` de 100 caractères à chaque lancement.

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

# Mémoire disponible, en mégaoctets. « available » et non « free » :
# c'est ce que le noyau peut réellement rendre sans passer par le swap.
avail_mb() { awk '/^MemAvailable:/ {print int($2/1024)}' /proc/meminfo; }

# Lance une commande sous plafond mémoire du noyau quand c'est possible.
# Sans systemd (ou sans cgroup v2), on lance quand même : le plafond est
# une ceinture de sécurité, pas une condition de fonctionnement.
capped() {
  local limit="$1"; shift
  if command -v systemd-run >/dev/null 2>&1 &&
     systemd-run --user --scope -p MemoryMax=64M --quiet -- /bin/true >/dev/null 2>&1; then
    systemd-run --user --scope --quiet -p MemoryMax="$limit" -- "$@"
  else
    echo "  (plafond mémoire indisponible sur ce système — lancement sans filet)" >&2
    "$@"
  fi
}

# Prévient AVANT de lancer, pendant qu'il est encore temps de fermer
# quelque chose. `need` est le pic mesuré, arrondi vers le haut.
preflight() {
  local need="$1" mode="$2" have
  have="$(avail_mb)"
  echo "Mémoire disponible : ${have} Mo — « ${mode} » a besoin d'environ ${need} Mo."
  if (( have < need )); then
    echo
    echo "  Ce n'est pas assez. Les plus gros consommateurs :"
    ps -eo rss,comm --sort=-rss | awk 'NR>1 && NR<=6 {printf "    %6.0f Mo  %s\n", $1/1024, $2}'
    echo
    echo "  Fermez-en un ou deux, puis relancez. Le plafond mémoire fera que"
    echo "  la compilation échouera proprement plutôt que d'emporter la session,"
    echo "  mais elle échouera quand même."
    echo
    read -r -p "  Continuer malgré tout ? [y/N] " reponse
    [[ "$reponse" == [yY] ]] || exit 1
  fi
  echo
}

case "${1:-dev}" in
  check)
    echo "Mémoire disponible : $(avail_mb) Mo"
    echo "  dev   (recommandé pour travailler) : ~1400 Mo"
    echo "  serve (démo, rien de résident)     : ~1900 Mo"
    echo
    echo "Ce qui consomme le plus en ce moment :"
    ps -eo rss,comm --sort=-rss | awk 'NR>1 && NR<=9 {printf "  %6.0f Mo  %s\n", $1/1024, $2}'
    ;;

  dev)
    # Le mode par défaut depuis le 21 septembre 2026 : c'est celui qui a
    # le pic le plus bas ET le rechargement à chaud. On ne lance pas de
    # navigateur : on ouvre l'adresse dans celui qui est déjà ouvert.
    preflight 1400 dev
    echo "Rechargement à chaud. Ouvrez http://localhost:$PORT dans le navigateur déjà ouvert."
    echo "  r = recharger · R = redémarrer · q = quitter"
    echo
    # Pas de `exec` ici : `capped` est une fonction du shell, et `exec` ne
    # sait remplacer le processus que par un vrai programme — il répondait
    # « exec: capped: not found » (corrigé le 21 septembre 2026). Le shell
    # parent qui reste coûte quelques mégaoctets et transmet aussi bien
    # Ctrl+C que les touches `r` / `R` / `q` de Flutter.
    capped 2000M flutter run -d web-server --web-port "$PORT" "${DEFINES[@]}"
    ;;

  serve)
    # Compile une fois, puis sert des fichiers statiques. Le compilateur
    # s'arrête à la fin : il ne reste qu'un serveur de quelques Mo. Pas de
    # rechargement à chaud — c'est le mode à laisser tourner pendant une
    # démo, pas celui pour travailler.
    preflight 1900 serve
    echo "Compilation (une fois, profil léger)…"
    # `-O1`            : optimisation minimale, bien plus légère que --release
    # `--no-source-maps` : les cartes de source doublent presque la mémoire
    # `--no-wasm-dry-run`: par défaut Flutter compile AUSSI en WebAssembly
    #                      « à blanc », juste pour d'éventuels avertissements
    capped 2400M flutter build web -O1 --no-source-maps --no-wasm-dry-run "${DEFINES[@]}"
    echo
    echo "  http://localhost:$PORT"
    echo "  Ctrl+C pour arrêter."
    echo
    # Le serveur de la bibliothèque standard Python : aucune dépendance à
    # installer, et une empreinte mémoire de l'ordre de 10 Mo.
    exec python3 -m http.server "$PORT" --directory build/web --bind 127.0.0.1
    ;;

  release)
    # Pour la mise en ligne seulement — et en principe c'est Netlify qui
    # s'en charge (voir netlify.toml). Mesuré à plus de 3 Go : fermez le
    # navigateur et l'éditeur avant, sinon la machine part en swap.
    preflight 3200 release
    capped 3600M flutter build web --release "${DEFINES[@]}"
    echo "Prêt dans build/web/"
    ;;

  *)
    echo "Usage: $0 [dev|serve|release|check]" >&2
    echo "  dev     rechargement à chaud, pic ~1,3 Go   (défaut)" >&2
    echo "  serve   compile puis sert, pic ~1,8 Go" >&2
    echo "  release compilation de mise en ligne, ~3 Go" >&2
    echo "  check   dit ce qui est disponible et ce qui consomme" >&2
    exit 1
    ;;
esac
