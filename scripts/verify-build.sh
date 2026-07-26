#!/usr/bin/env bash
# Post-build assertions.
#
# Franklin publishes anything in the working tree that config.md's `ignore`
# list does not name, so the deny-list fails open: a new file or directory is
# public by default. That has already happened three times (commits 270f9e3,
# 51f33bd, and data/cv_data.jl being served at /data/cv_data.jl). The point of
# this script is to turn that class of mistake from a silent leak into a failed
# build, so it is caught before deploy rather than after.
set -euo pipefail

site_dir="${1:-__site}"
status=0

if [[ ! -d "${site_dir}" ]]; then
  echo "error: build output not found: ${site_dir}" >&2
  exit 1
fi

fail() {
  echo "FAIL: $*" >&2
  status=1
}

# --- 1. No build-time sources may be published -------------------------------
# Julia/TOML/shell sources and dotfiles are inputs to the build, never content.
leaked="$(find "${site_dir}" \
  \( -name '*.jl' -o -name '*.toml' -o -name '*.sh' -o -name '.*' \) \
  -not -name '.' -print 2>/dev/null || true)"

if [[ -n "${leaked}" ]]; then
  fail "build-time sources published to ${site_dir}:"
  printf '  %s\n' ${leaked} >&2
  echo "  -> add the containing directory to the \`ignore\` list in config.md" >&2
fi

# --- 2. JSON-LD must parse ---------------------------------------------------
# _layout/head.html pastes raw JSON from config.md into a <script
# type="application/ld+json"> block. Malformed JSON there is invisible: the page
# renders fine and only structured-data consumers notice.
if command -v python3 >/dev/null 2>&1; then
  while IFS= read -r page; do
    python3 - "${page}" <<'PY' || fail "invalid JSON-LD in ${page}"
import json, re, sys
html = open(sys.argv[1], encoding="utf-8", errors="replace").read()
blocks = re.findall(
    r'<script[^>]*type=["\']application/ld\+json["\'][^>]*>(.*?)</script>',
    html, re.S | re.I)
for block in blocks:
    json.loads(block)
PY
  done < <(find "${site_dir}" -name '*.html' -print)
else
  echo "note: python3 not found; skipping JSON-LD validation" >&2
fi

# --- 3. Sitemap must be well-formed XML with no unrewritten /index.html ------
sitemap="${site_dir}/sitemap.xml"
if [[ -f "${sitemap}" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import sys,xml.dom.minidom as m; m.parse(sys.argv[1])" "${sitemap}" \
      || fail "sitemap.xml is not well-formed XML"
  fi
  if grep -q '<loc>[^<]*/index\.html</loc>' "${sitemap}"; then
    fail "sitemap.xml still contains /index.html URLs -- did normalize-generated-urls.sh run?"
  fi
fi

# --- 4. No unresolved Franklin template calls --------------------------------
# An hfun that is defined but not exported renders as literal {{...}} text
# rather than failing, which is how hfun_sitemap_xml went unnoticed.
unresolved="$(grep -rlE '\{\{[a-z_]+' --include='*.html' --include='*.xml' "${site_dir}" 2>/dev/null || true)"
if [[ -n "${unresolved}" ]]; then
  fail "unresolved {{...}} template calls in:"
  printf '  %s\n' ${unresolved} >&2
  echo "  -> the hfun is probably missing from the export block in src/site_utils.jl" >&2
fi

if [[ "${status}" -eq 0 ]]; then
  echo "Build verification passed: ${site_dir}"
fi
exit "${status}"
