#!/usr/bin/env bash
# =============================================================================
# audit.sh — CLI equivalent of the `audit` role (detective security controls)
# Mirrors: roles/audit — auditd + AIDE + OpenSCAP compliance scanning
# Run as root. These are REFERENCE commands — read the comments, run what you need.
# =============================================================================

# ---------------------------------------------------------------------------
# 1. auditd — the Linux kernel audit daemon (records security-relevant events)
# ---------------------------------------------------------------------------

# Install auditd
dnf -y install audit

# Deploy your audit rules (the role templates 99-platform.rules — the full set is in
# roles/audit/templates/audit.rules.j2). It loads last (99-) and ADDS to the stock
# rules.d/audit.rules, so it has no -D/-b/-f of its own. Excerpt:
cat > /etc/audit/rules.d/99-platform.rules <<'RULES'
## Identity / sudoers (watches: arch-independent, no b32 twin needed)
-w /etc/passwd -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/sudoers -p wa -k scope
-w /etc/sudoers.d/ -p wa -k scope
## Syscall rules: ALWAYS a b64/b32 pair. A 32-bit binary on x86_64 enters through
## the b32 table and bypasses a b64-only rule. b32 adds its 32-bit-only names.
-a always,exit -F arch=b64 -S adjtimex,settimeofday,clock_settime -k time-change
-a always,exit -F arch=b32 -S adjtimex,settimeofday,clock_settime,stime -k time-change
-a always,exit -F arch=b64 -S chown,fchown,fchownat,lchown -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b32 -S chown,fchown,fchownat,lchown,chown32,fchown32,lchown32 -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b64 -S init_module,finit_module,delete_module -k modules
-a always,exit -F arch=b32 -S init_module,finit_module,delete_module -k modules
## Include the modern variants (openat2, renameat2, umount2): a rule on the old name
## alone misses callers that use the new syscall.
-a always,exit -F arch=b64 -S open,openat,openat2,truncate,ftruncate -F exit=-EACCES -F auid>=1000 -F auid!=4294967295 -k access
-a always,exit -F arch=b32 -S open,openat,openat2,truncate,ftruncate,truncate64,ftruncate64 -F exit=-EACCES -F auid>=1000 -F auid!=4294967295 -k access
-a always,exit -F arch=b64 -S unlink,unlinkat,rename,renameat,renameat2 -F auid>=1000 -F auid!=4294967295 -k delete
-a always,exit -F arch=b32 -S unlink,unlinkat,rename,renameat,renameat2 -F auid>=1000 -F auid!=4294967295 -k delete
-a always,exit -F arch=b64 -S mount,umount2 -F auid>=1000 -F auid!=4294967295 -k mounts
-a always,exit -F arch=b32 -S mount,umount2 -F auid>=1000 -F auid!=4294967295 -k mounts
RULES
# Check a syscall name exists in an arch table before using it (else auditctl rejects the line):
ausyscall i386 stime --exact      # 25
ausyscall x86_64 stime --exact    # nothing: stime is b32-only
# Optional (CIS): append '-e 2' to make the rules immutable — role var audit_immutable,
# default false. After that, ANY rule change needs a reboot.

# Load the rules (without reboot, for the mutable ones)
augenrules --load          # regenerate + load rules.d
auditctl -l | grep -c 'arch=b32'   # b32 twins are live

# Enable + start the daemon
systemctl enable --now auditd

# --- Using auditd (the payoff) ---
auditctl -l                                  # list active rules
ausearch -k scope                            # search events by key (sudoers changes)
ausearch -m avc -ts recent                   # recent SELinux denials
aureport --summary                           # summary report
aureport -au                                 # authentication attempts

# ---------------------------------------------------------------------------
# 2. AIDE — Advanced Intrusion Detection Environment (file integrity monitoring)
# ---------------------------------------------------------------------------

# Install
dnf -y install aide

# Build the baseline LAST — after every service is installed and configured — or the
# first check reports every later change. The role does this in aide_baseline.yml, the
# final play of site.yml. First run only (takes a few minutes):
[ -f /var/lib/aide/aide.db.gz ] || aide --init

# Activate the baseline (AIDE writes .new, you promote it to the live db).
# Only move if the .new file still exists (idempotent):
[ -f /var/lib/aide/aide.db.new.gz ] && mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz

# Run an integrity check (compares current filesystem to the baseline)
aide --check

# After legitimate changes (e.g. a package update): review `aide --check` first, then
# rebuild. Use --init, not --update: --update exits non-zero whenever it finds changes,
# so `aide --update && mv ...` never moves the new DB in after a real change.
# Role equivalent: ansible-playbook aide_baseline.yml --limit <host> -e audit_aide_rebaseline=true
aide --init && mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz

# The role schedules this via a proper systemd timer (not cron).
# Nice/IOSchedulingClass: yield CPU + disk to real work. RandomizedDelaySec: spread
# nodes apart, including the Persistent=true catch-up run right after boot.
cat > /etc/systemd/system/aide-check.service <<'UNIT'
[Unit]
Description=AIDE file integrity check
[Service]
Type=oneshot
Nice=19
IOSchedulingClass=idle
ExecStart=/usr/sbin/aide --check
UNIT
cat > /etc/systemd/system/aide-check.timer <<'UNIT'
[Unit]
Description=Daily AIDE file integrity check
[Timer]
OnCalendar=*-*-* 05:00:00
RandomizedDelaySec=30min
Persistent=true
[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
systemctl enable --now aide-check.timer

# ---------------------------------------------------------------------------
# 3. OpenSCAP — compliance scanning against ANSSI BP-28 high profile
# ---------------------------------------------------------------------------

# Install the scanner + the SCAP Security Guide content
dnf -y install openscap-scanner scap-security-guide

# List available profiles in the RHEL 9 guide
oscap info /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml | grep -i profile

# Run a scan against the ANSSI BP-28 HIGH profile, producing an HTML report.
# Delete any old results file first, so the XML you parse is from THIS run.
mkdir -p /var/log/oscap && chmod 0750 /var/log/oscap
rm -f /var/log/oscap/results.xml
nice -n 19 ionice -c 3 oscap xccdf eval \
  --profile xccdf_org.ssgproject.content_profile_anssi_bp28_high \
  --results /var/log/oscap/results.xml \
  --report /var/log/oscap/report.html \
  /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml
RC=$?
# rc 0 = all pass, rc 2 = some rules failed (normal). ANY other rc is a scan error —
# and so is a 0/2 with no results XML. Don't publish a metric from a failed scan.
case "$RC" in 0|2) ;; *) echo "ERROR: oscap failed (rc=$RC)" >&2 ;; esac
[ -s /var/log/oscap/results.xml ] || echo "ERROR: oscap rc=$RC but no results XML" >&2

# Open report.html in a browser to see the scored pass/fail breakdown.

# --- Emit the score as a Prometheus metric (what the role does) ---
# Only after a good scan (above). grep -c prints 0 AND exits 1 on no match, so
# '|| echo 0' would give "0<newline>0" and break the arithmetic: use '|| true'.
PASS=$(grep -c '<result>pass</result>' /var/log/oscap/results.xml || true); PASS=${PASS:-0}
FAIL=$(grep -c '<result>fail</result>' /var/log/oscap/results.xml || true); FAIL=${FAIL:-0}
SCORED=$(( PASS + FAIL ))
[ "$SCORED" -gt 0 ] && SCORE=$(awk "BEGIN{printf \"%.2f\", ($PASS/$SCORED)*100}") || SCORE=0
cat > /var/lib/node_exporter/textfile_collector/compliance.prom <<PROM
# HELP compliance_score_percent Percent of scored rules passing.
# TYPE compliance_score_percent gauge
compliance_score_percent{profile="xccdf_org.ssgproject.content_profile_anssi_bp28_high"} $SCORE
# HELP compliance_last_scan_timestamp_seconds Unix time of last scan.
# TYPE compliance_last_scan_timestamp_seconds gauge
compliance_last_scan_timestamp_seconds $(date +%s)
PROM
# node_exporter (with --collector.textfile) then exposes this to Prometheus.
# A stale compliance_last_scan_timestamp_seconds means scans stopped succeeding.

# The role runs all of this from /usr/local/bin/oscap-scan.sh (exit 1 on scan error, so
# the unit shows failed) via a weekly, jittered, idle-priority timer:
cat > /etc/systemd/system/oscap-scan.service <<'UNIT'
[Unit]
Description=OpenSCAP compliance scan
[Service]
Type=oneshot
Nice=19
IOSchedulingClass=idle
ExecStart=/usr/local/bin/oscap-scan.sh
UNIT
cat > /etc/systemd/system/oscap-scan.timer <<'UNIT'
[Unit]
Description=Weekly OpenSCAP compliance scan
[Timer]
OnCalendar=Sun *-*-* 03:00:00
RandomizedDelaySec=1h
Persistent=true
[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
systemctl enable --now oscap-scan.timer
systemctl list-timers 'oscap-scan*' 'aide-check*'   # NEXT shows the random offset
