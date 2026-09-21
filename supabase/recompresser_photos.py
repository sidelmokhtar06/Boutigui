#!/usr/bin/env python3
"""
Recompresse en masse les photos déjà envoyées sur Supabase Storage.

**Pourquoi ce script existe.** Depuis le 9 septembre 2026, chaque nouvelle
photo envoyée depuis l'app passe automatiquement par une compression
(voir lib/services/image_compressor.dart et storage_service.dart) : grande
version 1200 px + vignette 500 px, en JPEG. Mais les photos envoyées AVANT
cette date sont restées telles quelles dans le stockage — souvent 3000 à
5000 px, plusieurs mégaoctets — ce qui recrée le bug des rectangles noirs
sur iPhone dès qu'une de ces vieilles photos s'affiche. Ce script les
retraite toutes, une bonne fois, avec exactement les mêmes réglages que
l'app (mêmes largeurs, même qualité, même règle de nommage de la vignette).

**Ce qu'il fait, bucket par bucket** (product-images, shop-images,
category-images, banner-images) :
  1. Liste tous les fichiers.
  2. Ignore les fichiers qui sont déjà une vignette (se terminant par
     `_thumb.jpg`) : ils sont retraités comme vignette d'une image
     principale, pas comme image principale eux-mêmes.
  3. Pour chaque image principale : télécharge, redimensionne à 1200 px de
     large si besoin, réencode en JPEG qualité 82 ; prépare aussi la
     vignette 500 px / qualité 78. Comme dans l'app, une image déjà petite
     et déjà bien compressée est laissée telle quelle plutôt que
     réencodée pour rien.
  4. Ré-envoie la version principale AU MÊME EMPLACEMENT (upsert) — les
     URLs déjà enregistrées en base ne bougent pas — puis envoie/actualise
     la vignette à côté.

**Sécurité : il faut la clé "service role", pas la clé publique.** La clé
publique (`anon`/`publishable`, celle utilisée par l'app) est bridée par les
règles de sécurité (RLS) et ne peut pas lister ni réécrire les fichiers de
tout le monde. La clé "service role" les contourne entièrement : à
récupérer dans Supabase > Project Settings > API > "service_role", à NE
JAMAIS mettre dans l'app ni dans un dépôt Git, à utiliser seulement ici,
en local, le temps du script.

**Toujours commencer par un essai à blanc (`--dry-run`, activé par
défaut)** : affiche ce qui serait fait, sans rien envoyer. Ajouter
`--apply` seulement une fois le résultat vérifié.

Installation (une fois) :
    pip install pillow requests --break-system-packages

Utilisation :
    export SUPABASE_URL="https://vxmgtcjkrjeexkrzicoo.supabase.co"
    export SUPABASE_SERVICE_KEY="...clé service_role, jamais la publique..."

    python3 recompresser_photos.py                # essai à blanc (rien n'est envoyé)
    python3 recompresser_photos.py --apply         # exécution réelle
    python3 recompresser_photos.py --apply --bucket product-images  # un seul bucket
"""

from __future__ import annotations

import argparse
import io
import os
import sys
from dataclasses import dataclass

try:
    import requests
    from PIL import Image
except ImportError:
    print("Modules manquants. Lancez d'abord :")
    print("  pip install pillow requests --break-system-packages")
    sys.exit(1)

# Mêmes réglages que lib/services/image_compressor.dart — à garder identiques
# si jamais ces valeurs changent côté app.
MAX_WIDTH = 1200
QUALITY = 82
THUMB_WIDTH = 500
THUMB_QUALITY = 78
THUMB_SUFFIX = "_thumb"
SKIP_UNDER_BYTES = 60 * 1024

BUCKETS = ["product-images", "shop-images", "category-images", "banner-images"]


@dataclass
class Prepared:
    bytes_: bytes
    filename: str
    changed: bool
    thumb_bytes: bytes | None
    thumb_filename: str | None


def prepare(raw: bytes, filename: str) -> Prepared:
    """Reproduit exactement ImageCompressor.prepare() (image_compressor.dart)."""
    try:
        img = Image.open(io.BytesIO(raw))
        img.load()
    except Exception:
        return Prepared(raw, filename, False, None, None)

    # JPEG ne garde pas la transparence — fond blanc, comme un export normal.
    if img.mode in ("RGBA", "P", "LA"):
        bg = Image.new("RGB", img.size, (255, 255, 255))
        bg.paste(img.convert("RGBA"), mask=img.convert("RGBA").split()[-1])
        img = bg
    else:
        img = img.convert("RGB")

    base, _, _ = filename.rpartition(".") if "." in filename else (filename, "", "")
    base = base or filename

    large = img
    if img.width > MAX_WIDTH:
        ratio = MAX_WIDTH / img.width
        large = img.resize((MAX_WIDTH, max(1, round(img.height * ratio))), Image.LANCZOS)

    main_buf = io.BytesIO()
    large.save(main_buf, format="JPEG", quality=QUALITY)
    main_bytes = main_buf.getvalue()
    main_filename = f"{base}.jpg"

    keep_original = len(main_bytes) >= len(raw) and len(raw) <= SKIP_UNDER_BYTES
    changed = not keep_original
    if keep_original:
        main_bytes = raw
        main_filename = filename

    small = img
    if img.width > THUMB_WIDTH:
        ratio = THUMB_WIDTH / img.width
        small = img.resize((THUMB_WIDTH, max(1, round(img.height * ratio))), Image.LANCZOS)
    thumb_buf = io.BytesIO()
    small.save(thumb_buf, format="JPEG", quality=THUMB_QUALITY)

    return Prepared(
        bytes_=main_bytes,
        filename=main_filename,
        changed=changed,
        thumb_bytes=thumb_buf.getvalue(),
        thumb_filename=f"{base}{THUMB_SUFFIX}.jpg",
    )


class SupabaseStorage:
    def __init__(self, url: str, service_key: str):
        self.base = url.rstrip("/")
        self.headers = {
            "Authorization": f"Bearer {service_key}",
            "apikey": service_key,
        }

    def list_all(self, bucket: str) -> list[dict]:
        objects: list[dict] = []
        offset = 0
        limit = 100
        while True:
            resp = requests.post(
                f"{self.base}/storage/v1/object/list/{bucket}",
                headers=self.headers,
                json={"prefix": "", "limit": limit, "offset": offset,
                      "sortBy": {"column": "name", "order": "asc"}},
                timeout=30,
            )
            resp.raise_for_status()
            batch = resp.json()
            if not batch:
                break
            # Supabase liste aussi les "dossiers" (uid/) sans métadonnée de
            # fichier : on les explore récursivement.
            for item in batch:
                if item.get("id") is None and item.get("name"):
                    sub_prefix = item["name"]
                    objects.extend(self._list_prefix(bucket, sub_prefix))
                else:
                    objects.append(item)
            if len(batch) < limit:
                break
            offset += limit
        return objects

    def _list_prefix(self, bucket: str, prefix: str) -> list[dict]:
        results = []
        offset = 0
        limit = 100
        while True:
            resp = requests.post(
                f"{self.base}/storage/v1/object/list/{bucket}",
                headers=self.headers,
                json={"prefix": prefix, "limit": limit, "offset": offset,
                      "sortBy": {"column": "name", "order": "asc"}},
                timeout=30,
            )
            resp.raise_for_status()
            batch = resp.json()
            if not batch:
                break
            for item in batch:
                full_name = f"{prefix}/{item['name']}"
                if item.get("id") is None:
                    results.extend(self._list_prefix(bucket, full_name))
                else:
                    item["name"] = full_name
                    results.append(item)
            if len(batch) < limit:
                break
            offset += limit
        return results

    def download(self, bucket: str, path: str) -> bytes:
        resp = requests.get(
            f"{self.base}/storage/v1/object/{bucket}/{path}",
            headers=self.headers, timeout=60,
        )
        resp.raise_for_status()
        return resp.content

    def upload(self, bucket: str, path: str, data: bytes) -> None:
        headers = {**self.headers, "Content-Type": "image/jpeg", "x-upsert": "true"}
        resp = requests.post(
            f"{self.base}/storage/v1/object/{bucket}/{path}",
            headers=headers, data=data, timeout=60,
        )
        resp.raise_for_status()


def human(n: int) -> str:
    for unit in ("o", "Ko", "Mo", "Go"):
        if n < 1024:
            return f"{n:.0f} {unit}"
        n /= 1024
    return f"{n:.1f} To"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--apply", action="store_true", help="Envoie réellement les fichiers (sinon, essai à blanc)")
    parser.add_argument("--bucket", choices=BUCKETS, help="Ne traiter qu'un seul bucket")
    args = parser.parse_args()

    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_SERVICE_KEY")
    if not url or not key:
        print("Il manque SUPABASE_URL et/ou SUPABASE_SERVICE_KEY (voir l'en-tête du fichier).")
        sys.exit(1)

    storage = SupabaseStorage(url, key)
    buckets = [args.bucket] if args.bucket else BUCKETS

    mode = "APPLICATION RÉELLE" if args.apply else "ESSAI À BLANC (rien n'est envoyé — ajoutez --apply pour de vrai)"
    print(f"=== {mode} ===\n")

    total_before = 0
    total_after = 0
    total_touched = 0
    total_skipped = 0
    total_errors = 0

    for bucket in buckets:
        print(f"--- {bucket} ---")
        try:
            objects = storage.list_all(bucket)
        except Exception as e:
            print(f"  Impossible de lister ce bucket : {e}")
            total_errors += 1
            continue

        mains = [o for o in objects if not o["name"].endswith(f"{THUMB_SUFFIX}.jpg")]
        print(f"  {len(mains)} photo(s) à examiner")

        for obj in mains:
            path = obj["name"]
            try:
                raw = storage.download(bucket, path)
            except Exception as e:
                print(f"  [ERREUR] téléchargement {path} : {e}")
                total_errors += 1
                continue

            prepared = prepare(raw, path)
            total_before += len(raw)

            if not prepared.changed and prepared.filename == path:
                total_after += len(raw)
                total_skipped += 1
                continue

            total_after += len(prepared.bytes_)
            total_touched += 1
            print(f"  {path} : {human(len(raw))} -> {human(len(prepared.bytes_))}"
                  + (" (renommé en .jpg)" if prepared.filename != path else ""))

            if args.apply:
                try:
                    storage.upload(bucket, prepared.filename, prepared.bytes_)
                    if prepared.thumb_bytes and prepared.thumb_filename:
                        storage.upload(bucket, prepared.thumb_filename, prepared.thumb_bytes)
                except Exception as e:
                    print(f"    [ERREUR] envoi {path} : {e}")
                    total_errors += 1

    print("\n=== Résumé ===")
    print(f"Photos déjà optimisées, laissées telles quelles : {total_skipped}")
    print(f"Photos {'recompressées' if args.apply else 'à recompresser'} : {total_touched}")
    if total_errors:
        print(f"Erreurs : {total_errors}")
    if total_before:
        print(f"Poids total : {human(total_before)} -> {human(total_after)}")

    if not args.apply and total_touched:
        print("\nCeci était un essai à blanc. Relancez avec --apply pour envoyer réellement les fichiers.")


if __name__ == "__main__":
    main()
