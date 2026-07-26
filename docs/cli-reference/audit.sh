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

# Deploy your audit rules (the role templates 99-platform.rules).
# Rules go in /etc/audit/rules.d/*.rules ; example high-value rules:
cat > /etc/audit/rules.d/99-platform.rules <<'RULES'
## Log changes to authentication config
-w /etc/passwd -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/sudoers -p wa -k priv_esc
-w /etc/sudoers.d/ -p wa -k priv_esc
## Log use of privileged commands
-a always,exit -F arch=b64 -S execve -F euid=0 -k root_cmd
## Log network config changes
-w /etc/hosts -p wa -k network
## Make the config immutable (must be last; needs reboot to change)
-e 2
RULES

# Load the rules (without reboot, for the mutable ones)
augenrules --load          # regenerate + load rules.d
auditctl -R /etc/audit/rules.d/99-platform.rules   # or load a file directly

# Enable + start the daemon
systemctl enable --now auditd

# --- Using auditd (the payoff) ---
auditctl -l                                  # list active rules
ausearch -k priv_esc                         # search events by key
ausearch -m avc -ts recent                   # recent SELinux denials
aureport --summary                           # summary report
aureport -au                                 # authentication attempts

# ---------------------------------------------------------------------------
# 2. AIDE — Advanced Intrusion Detection Environment (file integrity monitoring)
# ---------------------------------------------------------------------------

# Install
dnf -y install aide

# Initialize the baseline database (first run only — takes a few minutes).
# The role guards this with `creates: /var/lib/aide/aide.db.gz` — do the same by hand:
[ -f /var/lib/aide/aide.db.gz ] || aide --init

# Activate the baseline (AIDE writes .new, you promote it to the live db).
# Guarded the same way — only move if the .new file still exists (idempotent):
[ -f /var/lib/aide/aide.db.new.gz ] && mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz

# Run an integrity check (compares current filesystem to the baseline)
aide --check

# After legitimate changes (e.g. a package update), update the baseline:
aide --update && mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz

# The role schedules this via a proper systemd timer (not cron):
cat > /etc/systemd/system/aide-check.service <<'UNIT'
[Unit]
Description=AIDE integrity check
[Service]
Type=oneshot
ExecStart=/usr/sbin/aide --check
UNIT
cat > /etc/systemd/system/aide-check.timer <<'UNIT'
[Unit]
Description=Run AIDE check daily
[Timer]
OnCalendar=daily
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

# Run a scan against the ANSSI BP-28 HIGH profile, producing an HTML report
oscap xccdf eval \
  --profile xccdf_org.ssgproject.content_profile_anssi_bp28_high \
  --results /var/lib/oscap/results.xml \
  --report /var/lib/oscap/report.html \
  /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml
# NOTE: exit code 2 just means "some rules failed" — that's normal, not an error.

# Open report.html in a browser to see the scored pass/fail breakdown.

# --- Emit the score as a Prometheus metric (what the role does) ---
# Parse pass/fail from the results XML and write a textfile-collector metric:
PASS=$(grep -c '<result>pass</result>' /var/lib/oscap/results.xml)
FAIL=$(grep -c '<result>fail</result>' /var/lib/oscap/results.xml)
SCORE=$(awk "BEGIN{print ($PASS/($PASS+$FAIL))*100}")
cat > /var/lib/node_exporter/textfile_collector/compliance.prom <<PROM
# HELP compliance_score_percent OpenSCAP ANSSI BP-28 high pass rate
# TYPE compliance_score_percent gauge
compliance_score_percent $SCORE
PROM
# node_exporter (with --collector.textfile) then exposes this to Prometheus.
