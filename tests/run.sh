#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
pass=0
ok() { pass=$((pass+1)); printf '  ✓ %s\n' "$1"; }
export PATH="$PWD/tests/bin:/usr/bin:/bin"
chmod +x tests/bin/systemctl tests/bin/journalctl
completed="=== Backup completed: $(date) ==="
snapshot='snapshot 17e1da2d saved'
timeout_log=$(printf '%s\n' "$completed" "$snapshot" '=== Backup started: Fri Aug 28 05:13:41 PM EDT 2026 ===' \
  'vic-backup.service: start operation timed out. Terminating.' \
  'vic-backup.service: Main process exited, code=exited, status=130/n/a' \
  "vic-backup.service: Failed with result 'timeout'.")
export JOURNAL_CAT="$timeout_log" JOURNAL_ISO="$timeout_log"
out=$(./status)
jq -e '.state=="failed" and .result=="timeout (status 130)" and .failures7d==1' <<<"$out" >/dev/null \
  && ok 'latest timeout/status 130 overrides misleading systemctl Result=success' \
  || { printf '  ✗ timeout fixture: %s\n' "$out"; exit 1; }

retry_log=$(printf '%s\n' "$timeout_log" "=== Backup started: $(date --date='2 minutes ago') ===" \
  'snapshot 077410ae saved' "=== Backup completed: $(date) ===")
export JOURNAL_CAT="$retry_log" JOURNAL_ISO="$retry_log"
out=$(./status)
jq -e '.state=="healthy" and .result=="success" and .snapshot=="077410ae" and .failures7d==1' <<<"$out" >/dev/null \
  && ok 'successful retry clears current failure but retains historical failure count' \
  || { printf '  ✗ retry fixture: %s\n' "$out"; exit 1; }
printf '%s\n' "$pass passed"
