#!/usr/bin/env bash
# Deploy this source checkout to the live Omarchy plugin dir, then restart the shell.
# Live dir may have in-place edits — diff first (Fred's rule: status/backup/MERGE before rsync).
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
DST="$HOME/.config/omarchy/plugins/pi.backup-monitor"
# Repo-only files: they are not part of the plugin, so they are neither copied
# nor counted as drift — otherwise every deploy would trip the guard below.
EXCLUDE=(--exclude=.git --exclude=deploy.sh --exclude=README.md --exclude=assets)

if ! diff -rq "${EXCLUDE[@]}" "$SRC" "$DST" >/dev/null; then
  echo "Live dir differs from source:"; diff -rq "${EXCLUDE[@]}" "$SRC" "$DST" || true
  [[ "${1:-}" == "--force" ]] || { echo "Re-run with --force to overwrite live."; exit 1; }
fi
rsync -a --delete "${EXCLUDE[@]}" "$SRC/" "$DST/"
omarchy-restart-shell
