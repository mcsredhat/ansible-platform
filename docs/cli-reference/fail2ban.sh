#!/usr/bin/env bash
# =============================================================================
# fail2ban.sh — CLI equivalent of the `fail2ban` role (network-layer IP banning)
# Mirrors: roles/fail2ban/tasks/main.yml — verified line-by-line against source.
# Run as root. Complements faillock: faillock locks the ACCOUNT, fail2ban bans
# the IP at firewalld. The base role covers sshd on EVERY node; tiers extend
# the jail list (web/edge add nginx, mail adds postfix/dovecot).
# =============================================================================

dnf -y install fail2ban fail2ban-firewalld

# Ignore loopback + the management subnet so a bad login can't lock you out.
# NARROW this to just your jump/mgmt hosts in real production.
cat > /etc/fail2ban/jail.d/10-platform.local <<'JAILS'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
banaction = firewallcmd-rich-rules
ignoreip = 127.0.0.1/8 ::1 10.50.1.0/24

[sshd]
enabled = true
backend = systemd
JAILS

# --- On the edge/web tier, ADD (don't replace) an nginx jail: ---
# cat >> /etc/fail2ban/jail.d/10-platform.local <<'JAILS'
#
# [nginx-http-auth]
# enabled = true
# JAILS

# --- On the mail host, ADD Postfix/Dovecot jails: ---
# cat >> /etc/fail2ban/jail.d/10-platform.local <<'JAILS'
#
# [postfix]
# enabled = true
# port    = smtp,submission,smtps
# logpath = /var/log/maillog
#
# [dovecot]
# enabled = true
# port    = imap,imaps,pop3,pop3s,submission,smtps
# logpath = /var/log/maillog
# JAILS

systemctl enable --now fail2ban

# --- Operating ---
fail2ban-client status                    # list active jails
fail2ban-client status sshd               # detail: banned IPs, failures
fail2ban-client set sshd unbanip 1.2.3.4  # unban an IP
tail -f /var/log/fail2ban.log             # watch bans happen
