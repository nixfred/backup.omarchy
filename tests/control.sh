#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
export BACKUP_MONITOR_UNIT=fixture-backup
export BACKUP_TEST_ROOT="$sandbox"
export BACKUP_TEST_SYSTEMCTL_LOG="$sandbox/systemctl.log"

mkdir -p "$sandbox/etc/systemd/system/fixture-backup.timer.d"
./control schedule six-hourly

grep -Fx 'SCHEDULE_PRESET=six-hourly' "$sandbox/etc/fixture-backup-control.conf" >/dev/null
grep -Fx 'OnCalendar=*-*-* 00,06,12,18:00:00' "$sandbox/etc/systemd/system/fixture-backup.timer.d/schedule.conf" >/dev/null
grep -Fx 'daemon-reload' "$BACKUP_TEST_SYSTEMCTL_LOG" >/dev/null
grep -Fx 'enable --now fixture-backup.timer' "$BACKUP_TEST_SYSTEMCTL_LOG" >/dev/null
grep -Fx 'restart fixture-backup.timer' "$BACKUP_TEST_SYSTEMCTL_LOG" >/dev/null
printf '  ✓ six-hour schedule writes an allowlisted drop-in and activates it\n'
