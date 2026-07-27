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
if command -v python3 >/dev/null 2>&1; then
  unresolved="$(python3 - "${site_dir}" <<'PY' || true
import re, os, sys
import glob
site_dir = sys.argv[1]
pattern = re.compile(r'\{\{[a-z_]+')
bad_files = []

for html_file in glob.glob(os.path.join(site_dir, '**/*.html'), recursive=True):
    with open(html_file, 'r', encoding='utf-8', errors='replace') as f:
        content = f.read()

    # Strip <pre ...>...</pre> and <code ...>...</code> regions
    content = re.sub(r'<pre[^>]*>.*?</pre>', '', content, flags=re.DOTALL | re.IGNORECASE)
    content = re.sub(r'<code[^>]*>.*?</code>', '', content, flags=re.DOTALL | re.IGNORECASE)

    if pattern.search(content):
        bad_files.append(html_file.replace(site_dir + '/', ''))

for xml_file in glob.glob(os.path.join(site_dir, '**/*.xml'), recursive=True):
    with open(xml_file, 'r', encoding='utf-8', errors='replace') as f:
        content = f.read()

    if pattern.search(content):
        bad_files.append(xml_file.replace(site_dir + '/', ''))

for f in bad_files:
    print(f)
PY
  )"
else
  unresolved="$(grep -rlE '\{\{[a-z_]+' --include='*.html' --include='*.xml' "${site_dir}" 2>/dev/null || true)"
fi

if [[ -n "${unresolved}" ]]; then
  fail "unresolved {{...}} template calls in:"
  printf '  %s\n' ${unresolved} >&2
  echo "  -> the hfun is probably missing from the export block in src/site_utils.jl" >&2
fi

# --- 5. Theme bootstrap must be inlined in every page -----------------------
# The theme script must run before first paint. If it is ever moved to an
# external file or dropped, every page loads in the wrong theme and flashes.
missing_theme=0
while IFS= read -r page; do
  if ! grep -q '__toggleTheme' "${page}"; then
    missing_theme=$((missing_theme + 1))
  fi
done < <(find "${site_dir}" -name '*.html' -not -path "${site_dir}/assets/*" -print)

if [[ "${missing_theme}" -gt 0 ]]; then
  fail "${missing_theme} page(s) lack the inline theme bootstrap"
  echo "  -> the script belongs in _layout/head.html, inlined, before first paint" >&2
fi

# --- 6. Colour literals may live only in token declarations -----------------
# 62 hex literals used to be scattered through site.css, which made dark mode
# impossible. Scanning emitted HTML alone would pass while the stylesheet
# stayed un-themeable, so this targets the stylesheet itself.
css="${site_dir}/assets/css/site.css"
if [[ -f "${css}" ]]; then
  stray="$(python3 - "${css}" <<'PY'
import re, sys
css = open(sys.argv[1], encoding="utf-8", errors="replace").read()
# Strip the vendored highlight.js themes — they are third-party CSS whose
# palette is not ours to tokenise. They are between sentinel comments.
css = re.sub(r'/\* --- BEGIN VENDORED HIGHLIGHT\.JS THEMES --- \*/.*?/\* --- END VENDORED HIGHLIGHT\.JS THEMES --- \*/', '', css, flags=re.DOTALL)
# Strip comments AFTER the sentinel block (which is itself delimited by
# comments, so this must not run first). A colour named in a comment renders
# nothing; failing the build over documentation would just teach people to
# stop explaining their colour choices.
css = re.sub(r'/\*.*?\*/', '', css, flags=re.DOTALL)
# Remove the token declaration blocks, then look for what survives.
css = re.sub(r':root(?:\[data-theme="[a-z]+"\])?\s*\{[^}]*\}', '', css)
css = re.sub(r'@media\s*\(prefers-color-scheme:\s*dark\)\s*\{(?:[^{}]|\{[^}]*\})*\}', '', css)
# NOTE: .dark-zone used to be exempted here because it hardcoded its text
# colours. It no longer needs an exemption: content on permanently-dark
# surfaces now uses the --on-raised-* tokens, declared once in :root with no
# dark-theme override. If you find yourself wanting to add an exemption,
# add a token instead — an exemption list is how the theme rots.
hits = re.findall(r'#[0-9a-fA-F]{3,8}\b', css)

# Named CSS colours leak the theme just as badly as hex, and are easier to
# miss: `border: 1px solid lightgrey` looked harmless and shipped a bright
# rule onto the dark theme, while `solid black` was invisible on it. Only
# inspect colour-bearing properties, so `white-space: normal` is not a hit.
NAMED = (r'\b(?:white|black|silver|gray|grey|lightgray|lightgrey|darkgray|'
         r'darkgrey|gainsboro|whitesmoke|ivory|snow|beige|navy|teal|olive|'
         r'maroon|aqua|fuchsia|lime|red|blue|green|yellow|orange|purple|'
         r'pink|brown|gold|tan|cyan|magenta)\b')
for prop in re.finditer(r'(?:^|[;{])\s*(?:color|background|background-color|'
                        r'border[a-z-]*|outline[a-z-]*|fill|stroke|'
                        r'text-decoration-color|box-shadow)\s*:([^;}]*)', css):
    for name in re.findall(NAMED, prop.group(1), re.I):
        hits.append(name)

print("\n".join(sorted(set(hits))))
PY
)"
  if [[ -n "${stray}" ]]; then
    fail "colour literals outside token blocks in site.css:"
    printf '  %s\n' ${stray} >&2
    echo "  -> replace with var(--paper|--wash|--line|--ink|--muted|--accent|...)" >&2
    echo "  -> named colours (lightgrey, black, white) leak too: they do not invert" >&2
  fi
fi

# --- 7. No colour literals in emitted HTML ----------------------------------
# Inline style="color:#..." in Markdown and Julia emitters bypasses the token
# layer entirely and is invisible until someone switches theme.
inline_colour="$(grep -rlE 'style="[^"]*(color|background)[^"]*#[0-9a-fA-F]{3,8}' \
  --include='*.html' "${site_dir}" 2>/dev/null || true)"
if [[ -n "${inline_colour}" ]]; then
  fail "inline colour literals in emitted HTML:"
  printf '  %s\n' ${inline_colour} >&2
  echo "  -> move to a class in _assets/css/site.css that uses var(--...)" >&2
fi

# --- 8. Self-hosted fonts must publish --------------------------------------
# Franklin's ignore list fails open in one direction and silently drops
# unreferenced directories in the other. A missing woff2 degrades to a system
# fallback that looks almost right, so this must be asserted, not eyeballed.
for font in instrument-serif-400 instrument-serif-400-italic \
            source-sans-3-400 source-sans-3-600; do
  if [[ ! -f "${site_dir}/assets/fonts/${font}.woff2" ]]; then
    fail "missing font: assets/fonts/${font}.woff2"
  fi
done

# --- 9. Dead stylesheets must not be published ------------------------------
# These were linked by no template but shipped on every deploy. Franklin
# republishes anything left in the working tree, so deletion needs a guard.
for dead in css/franklin.css css/poole_hyde.css assets/css/style.css; do
  if [[ -f "${site_dir}/${dead}" ]]; then
    fail "dead stylesheet published: ${dead}"
  fi
done

if [[ "${status}" -eq 0 ]]; then
  echo "Build verification passed: ${site_dir}"
fi
exit "${status}"
