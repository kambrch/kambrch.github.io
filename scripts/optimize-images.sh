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

# Fed by process substitution rather than a pipe: a pipeline would run this
# loop in a subshell, where `set -e` cannot abort the script and an encoder
# failure would still exit 0. -print0 also survives filenames with spaces.
while IFS= read -r -d '' file; do
  filename="$(basename "$file")"
  # Skip our own derivatives only. A bare -[0-9]+ also matched legitimate
  # sources such as board-rev2.jpg, silently leaving them unoptimized.
  if [[ "$filename" =~ -(480|800|1200)\.(jpg|jpeg|png)$ ]]; then
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

    # No `|| true` here: silencing both branches is why zero .avif files were
    # ever produced while the script still reported success. `--quiet` is not an
    # avifenc option (it exits 2), and --min/--max are deprecated in favour of
    # -q 0..100 -- both failures were invisible behind the old `|| true`.
    avif_out="${base}-${width}.avif"
    if [ "$has_avifenc" -eq 1 ]; then
      avifenc -q "$AVIF_QUALITY" "$tmp" "$avif_out" >/dev/null
    else
      magick "$tmp" -strip -quality "$AVIF_QUALITY" "$avif_out"
    fi

    rm -f "$tmp"
  done
done < <(find "$INPUT_DIR" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) -print0)

echo "Done."
