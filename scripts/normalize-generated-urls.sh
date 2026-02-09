#!/usr/bin/env bash
set -euo pipefail

site_dir="${1:-__site}"
sitemap_file="${site_dir}/sitemap.xml"

if [[ ! -f "${sitemap_file}" ]]; then
  echo "Skipping URL normalization: ${sitemap_file} not found."
  exit 0
fi

# Franklin emits sitemap loc entries ending with /index.html.
# Normalize them to trailing-slash canonical URLs.
tmp_file="$(mktemp)"
sed -E 's#(<loc>https?://[^<]*)/index\.html</loc>#\1/</loc>#g' "${sitemap_file}" > "${tmp_file}"
mv "${tmp_file}" "${sitemap_file}"

echo "Normalized sitemap URLs in ${sitemap_file}"
