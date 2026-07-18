#!/bin/bash
# Run an AIDE check and emit an integrity metric for the node_exporter
# textfile collector. Exit code / changed-count feeds AideIntegrityChanged.
PROM_DIR="/var/lib/node_exporter/textfile_collector"
PROM="${PROM_DIR}/aide.prom"
TMP="$(mktemp)"

# aide --check exits non-zero when changes are detected.
OUT="$(/usr/sbin/aide --check 2>/dev/null)"
RC=$?

# Count reported changes (added/removed/changed entries).
CHANGED=$(echo "$OUT" | /usr/bin/grep -cE '^(added|removed|changed):' || true)
CHANGED=${CHANGED:-0}

{
  echo "# HELP aide_check_changed_files Number of files AIDE reports changed."
  echo "# TYPE aide_check_changed_files gauge"
  echo "aide_check_changed_files $CHANGED"
  echo "# HELP aide_check_last_run_timestamp_seconds Unix time of last AIDE check."
  echo "# TYPE aide_check_last_run_timestamp_seconds gauge"
  echo "aide_check_last_run_timestamp_seconds $(date +%s)"
  echo "# HELP aide_check_rc Exit code of the last AIDE check (0=clean)."
  echo "# TYPE aide_check_rc gauge"
  echo "aide_check_rc $RC"
} > "$TMP"

/usr/bin/install -m 0644 "$TMP" "$PROM"
/usr/bin/rm -f "$TMP"
