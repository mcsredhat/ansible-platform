#!/usr/bin/env bash
# =============================================================================
# mail_dns.sh — CLI equivalent of `mail_dns` (deliverability records)
# Mirrors: roles/mail_dns/tasks/main.yml — verified against source.
# Run as root (mail1). NOTE: this self-hosts authoritative DNS for the LAB.
# For a PUBLIC domain, publish these same records at your registrar/Cloudflare
# instead — don't self-host BIND for production mail DNS.
# =============================================================================

dnf -y install bind bind-utils

cat > /var/named/platform.lab.zone <<'ZONE'
$TTL 3600
@   IN SOA mail1.platform.lab. admin.platform.lab. (2026072601 3600 900 604800 86400)
@   IN NS  mail1.platform.lab.
@   IN MX  10 mail.platform.lab.
mail IN A 192.168.1.51
; SPF — only our MX may send for this domain (hard fail others)
@   IN TXT "v=spf1 mx -all"
; DKIM — paste the p= value from mail_rspamd.sh's generated .txt file
mail._domainkey IN TXT "v=DKIM1; k=rsa; p=PUBLIC_KEY_HERE"
; DMARC — quarantine (not reject) + aggregate reports
_dmarc IN TXT "v=DMARC1; p=quarantine; rua=mailto:postmaster@platform.lab"
; MTA-STS + TLS-RPT (transport security policy)
_mta-sts IN TXT "v=STSv1; id=2026072601"
_smtp._tls IN TXT "v=TLSRPTv1; rua=mailto:postmaster@platform.lab"
ZONE
chown root:named /var/named/platform.lab.zone
chmod 0640 /var/named/platform.lab.zone

firewall-cmd --permanent --add-service=dns
firewall-cmd --reload
systemctl enable --now named

# --- Verify the records resolve ---
dig @127.0.0.1 platform.lab MX +short
dig @127.0.0.1 platform.lab TXT +short
dig @127.0.0.1 _dmarc.platform.lab TXT +short
dig @127.0.0.1 mail._domainkey.platform.lab TXT +short
