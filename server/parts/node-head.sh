#!/usr/bin/env bash
# AFGHAN VPN node installer. Run ONCE as root on a fresh Ubuntu 22.04/24.04 server:
#   BACKEND_IP=<ip of your backend server> bash install-node.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run as root"; exit 1; }
: "${BACKEND_IP:?Set BACKEND_IP=<backend server IP address>}"
[[ "$BACKEND_IP" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || { echo "BACKEND_IP must be an IPv4 address"; exit 1; }
IFACE=$(ip -4 route show default | awk '{print $5; exit}')
export DEBIAN_FRONTEND=noninteractive
apt-get update -y && apt-get install -y wireguard ufw iptables python3 openssl fail2ban unattended-upgrades

umask 077
mkdir -p /etc/afghanvpn /var/lib/afghanvpn /opt/afghanvpn
cat > /etc/wireguard/fw.sh <<'FWEOF'
#!/bin/sh
# Firewall for VPN users: no user-to-user traffic, no access to private/provider networks, no outgoing SMTP (spam).
EXT=%IFACE%
RULES="
FORWARD|-i wg0 -p tcp --dport 25 -j DROP
FORWARD|-i wg0 -d 10.0.0.0/8 -j DROP
FORWARD|-i wg0 -d 172.16.0.0/12 -j DROP
FORWARD|-i wg0 -d 192.168.0.0/16 -j DROP
FORWARD|-i wg0 -d 169.254.0.0/16 -j DROP
FORWARD|-i wg0 -j ACCEPT
FORWARD|-o wg0 -j ACCEPT
INPUT|-i wg0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
INPUT|-i wg0 -p tcp --dport 443 -j ACCEPT
INPUT|-i wg0 -j DROP
"
if [ "$1" = up ]; then
  echo "$RULES" | grep . | tac | while IFS='|' read -r ch r; do iptables -I $ch 1 $r; done
  iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o $EXT -j MASQUERADE
else
  echo "$RULES" | grep . | while IFS='|' read -r ch r; do iptables -D $ch $r || true; done
  iptables -t nat -D POSTROUTING -s 10.8.0.0/24 -o $EXT -j MASQUERADE || true
fi
FWEOF
sed -i "s#%IFACE%#$IFACE#" /etc/wireguard/fw.sh; chmod 700 /etc/wireguard/fw.sh
if [ ! -f /etc/wireguard/server.key ]; then
  wg genkey | tee /etc/wireguard/server.key | wg pubkey > /etc/wireguard/server.pub
  cat > /etc/wireguard/wg0.conf <<CONF
[Interface]
Address = 10.8.0.1/24
ListenPort = 51820
PrivateKey = $(cat /etc/wireguard/server.key)
PostUp = /etc/wireguard/fw.sh up
PostDown = /etc/wireguard/fw.sh down
CONF
fi
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-wg.conf; sysctl --system >/dev/null

# agent identity: private TLS cert + shared secret
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 3650 \
  -keyout /etc/afghanvpn/agent.key -out /etc/afghanvpn/agent.crt -subj "/CN=afghanvpn-node" 2>/dev/null
FP=$(openssl x509 -in /etc/afghanvpn/agent.crt -outform DER | sha256sum | cut -d' ' -f1)
SECRET=$(openssl rand -hex 32)
printf "NODE_SECRET=%s\nCAPACITY=100\nCLIENT_DNS=1.1.1.1,1.0.0.1\n" "$SECRET" > /etc/afghanvpn/agent.env
chmod 600 /etc/afghanvpn/*

cat > /opt/afghanvpn/agent.py <<'AGENT_EOF'
