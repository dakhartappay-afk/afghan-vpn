#!/usr/bin/env bash
# AFGHAN VPN backend installer. Ubuntu 24.04, run as root:
#   DOMAIN=your.domain bash install-backend.sh      (DOMAIN's DNS A-record must already point to this server)
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run as root"; exit 1; }
: "${DOMAIN:?Set DOMAIN=your.domain}"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y && apt-get install -y python3 python3-venv curl ufw openssl caddy fail2ban unattended-upgrades
id afghanvpn-api >/dev/null 2>&1 || useradd --system --home-dir /opt/afghanvpn-api --shell /usr/sbin/nologin afghanvpn-api
install -d -m 755 /opt/afghanvpn-api
install -d -m 700 -o afghanvpn-api -g afghanvpn-api /var/lib/afghanvpn-api
printf "fastapi==0.115.0\nuvicorn==0.30.6\n" > /opt/afghanvpn-api/requirements.txt
cat > /opt/afghanvpn-api/main.py <<'MAIN_EOF'
