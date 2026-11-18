MAIN_EOF
python3 -m venv /opt/afghanvpn-api/venv
/opt/afghanvpn-api/venv/bin/pip install -q -r /opt/afghanvpn-api/requirements.txt
if [ ! -f /etc/afghanvpn-api.env ]; then ( umask 077; echo "ADMIN_TOKEN=$(openssl rand -hex 32)" > /etc/afghanvpn-api.env ); fi
chmod 600 /etc/afghanvpn-api.env

cat > /etc/systemd/system/afghanvpn-api.service <<UNIT
[Unit]
Description=AFGHAN VPN backend
After=network-online.target
[Service]
User=afghanvpn-api
WorkingDirectory=/opt/afghanvpn-api
EnvironmentFile=/etc/afghanvpn-api.env
Environment=DB_PATH=/var/lib/afghanvpn-api/afghanvpn.db
ExecStart=/opt/afghanvpn-api/venv/bin/uvicorn main:app --host 127.0.0.1 --port 8000 --proxy-headers --forwarded-allow-ips=127.0.0.1 --no-access-log
Restart=always
NoNewPrivileges=true
ProtectHome=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/var/lib/afghanvpn-api
[Install]
WantedBy=multi-user.target
UNIT

cat > /etc/caddy/Caddyfile <<CADDY
$DOMAIN {
    request_body {
        max_size 10KB
    }
    reverse_proxy 127.0.0.1:8000
}
CADDY

cat > /usr/local/bin/afghanvpn-admin <<'ADM'
#!/usr/bin/env bash
# Admin helper (run as root on the backend server). Reads the admin token locally; it is never shown.
set -euo pipefail
. /etc/afghanvpn-api.env
API=http://127.0.0.1:8000
req() { if [ -n "${3:-}" ]; then curl -fsS -X "$1" -H "X-Admin-Token: $ADMIN_TOKEN" -H "Content-Type: application/json" -d "$3" "$API$2"; else curl -fsS -X "$1" -H "X-Admin-Token: $ADMIN_TOKEN" "$API$2"; fi; echo; }
case "${1:-}" in
  invite)     req POST /admin/invites ;;
  servers)    req GET /admin/servers ;;
  devices)    req GET /admin/devices ;;
  revoke)     req POST "/admin/devices/$2/revoke" ;;
  enable)     req POST "/admin/servers/$2/enabled/1" ;;
  disable)    req POST "/admin/servers/$2/enabled/0" ;;
  remove)     req DELETE "/admin/servers/$2" ;;
  add-server) [ $# -eq 9 ] || { echo "usage: add-server ID COUNTRY CODE CITY HOST AGENT_FP AGENT_SECRET WG_PUBLIC_KEY"; exit 1; }
              req POST /admin/servers "$(python3 -c 'import json,sys; print(json.dumps(dict(zip(["id","country","code","city","host","agent_fp","agent_secret","wg_public_key"],sys.argv[1:]))))' "${@:2}")" ;;
  *) echo "commands: invite | servers | devices | revoke ID | enable ID | disable ID | remove ID | add-server ..."; exit 1 ;;
esac
ADM
chmod 700 /usr/local/bin/afghanvpn-admin

ufw limit OpenSSH; ufw allow 80/tcp; ufw allow 443/tcp; ufw --force enable
systemctl enable --now fail2ban
systemctl daemon-reload
systemctl enable --now afghanvpn-api
systemctl restart caddy
sleep 3
echo "Backend installed. Test (should print 401, which proves HTTPS + login protection work):"
curl -s -o /dev/null -w "%{http_code}\n" "https://$DOMAIN/v1/servers" || echo "HTTPS not ready yet: check that $DOMAIN points to this server, then run: systemctl restart caddy"
echo "Next: afghanvpn-admin invite"
