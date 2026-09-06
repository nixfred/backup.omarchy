#!/usr/bin/env bash
# Deploy this source checkout to the live Omarchy plugin dir, then restart the shell.
# Live dir may have in-place edits — diff first (Fred's rule: status/backup/MERGE before rsync).
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
DST="$HOME/.config/omarchy/plugins/pi.backup-monitor"
if ! diff -rq --exclude=.git --exclude=deploy.sh "$SRC" "$DST" >/dev/null; then
  echo "Live dir differs from source:"; diff -rq --exclude=.git --exclude=deploy.sh "$SRC" "$DST" || true
  [[ "${1:-}" == "--force" ]] || { echo "Re-run with --force to overwrite live."; exit 1; }
fi
rsync -a --delete --exclude=.git --exclude=deploy.sh "$SRC/" "$DST/"
omarchy-restart-shell
