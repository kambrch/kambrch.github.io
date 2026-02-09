#!/usr/bin/env bash
set -euo pipefail

INPUT_DIR="${1:-_assets/img}"
WEBP_QUALITY="${WEBP_QUALITY:-78}"
AVIF_QUALITY="${AVIF_QUALITY:-50}"
JPG_QUALITY="${JPG_QUALITY:-82}"
WIDTHS=(${WIDTHS:-480 800 1200})

if ! command -v magick >/dev/null 2>&1; then
  echo "error: ImageMagick ('magick') is required." >&2
  exit 1
fi

if [ ! -d "$INPUT_DIR" ]; then
  echo "error: input directory not found: $INPUT_DIR" >&2
  exit 1
fi

has_cwebp=0
command -v cwebp >/dev/null 2>&1 && has_cwebp=1
has_avifenc=0
command -v avifenc >/dev/null 2>&1 && has_avifenc=1

echo "Optimizing images in: $INPUT_DIR"
echo "Widths: ${WIDTHS[*]}"

find "$INPUT_DIR" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) | while read -r file; do
  filename="$(basename "$file")"
  if [[ "$filename" =~ -[0-9]+\.(jpg|jpeg|png)$ ]]; then
    continue
  fi

  ext="${filename##*.}"
  ext="${ext,,}"
  base="${file%.*}"

  echo "→ $file"
  for width in "${WIDTHS[@]}"; do
    tmp="${base}.tmp-${width}.png"
    magick "$file" -auto-orient -strip -resize "${width}x>" "$tmp"

    fallback="${base}-${width}.${ext}"
    if [[ "$ext" == "png" ]]; then
      magick "$tmp" -strip "$fallback"
    else
      magick "$tmp" -strip -quality "$JPG_QUALITY" "$fallback"
    fi

    webp_out="${base}-${width}.webp"
    if [ "$has_cwebp" -eq 1 ]; then
      cwebp -quiet -q "$WEBP_QUALITY" "$tmp" -o "$webp_out"
    else
      magick "$tmp" -strip -quality "$WEBP_QUALITY" "$webp_out"
    fi

    avif_out="${base}-${width}.avif"
    if [ "$has_avifenc" -eq 1 ]; then
      avifenc --quiet --min 20 --max "$AVIF_QUALITY" "$tmp" "$avif_out" >/dev/null 2>&1 || true
    else
      magick "$tmp" -strip -quality "$AVIF_QUALITY" "$avif_out" >/dev/null 2>&1 || true
    fi

    rm -f "$tmp"
  done
done

echo "Done."
