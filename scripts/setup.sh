#!/usr/bin/env bash
set -euo pipefail
cd /workspace/TDExtract
source scripts/environment.sh
if [[ "$(godot --version)" != 4.6.3.stable* ]]; then
  echo 'Godot 4.6.3 stable is required.' >&2
  exit 1
fi
template_dir="$XDG_DATA_HOME/godot/export_templates/4.6.3.stable"
if [[ ! -f "$template_dir/web_nothreads_release.zip" || ! -f "$template_dir/web_nothreads_debug.zip" ]]; then
  archive="${GODOT_TEMPLATE_ARCHIVE:-$(mktemp /tmp/tdextract-templates.XXXXXX.tpz)}"
  if [[ -z "${GODOT_TEMPLATE_ARCHIVE:-}" ]]; then
    curl -fsSL --retry 2 --max-time 600 -o "$archive" https://github.com/godotengine/godot/releases/download/4.6.3-stable/Godot_v4.6.3-stable_export_templates.tpz
  fi
  expected='da606b61c10157844f8300172df374472665f95015495cb1a7cd132c40ede404faa96cc1016a4b9662db9909ddea69632c4948b2cd11163438dad4808881fb68'
  actual="$(sha512sum "$archive")"
  [[ "${actual%% *}" == "$expected" ]] || { echo 'Godot template checksum mismatch' >&2; exit 1; }
  mkdir -p "$template_dir"
  unzip -jo "$archive" templates/web_nothreads_release.zip templates/web_nothreads_debug.zip -d "$template_dir"
  if [[ -z "${GODOT_TEMPLATE_ARCHIVE:-}" ]]; then rm "$archive"; fi
fi
mkdir -p build/web
godot --headless --path . --editor --quit
timeout 20 godot --headless --path . --script res://tests/smoke.gd
godot --headless --path . --export-release Web build/web/index.html
