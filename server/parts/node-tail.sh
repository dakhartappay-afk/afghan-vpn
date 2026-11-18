AGENT_EOF
chmod 700 /opt/afghanvpn/agent.py

cat > /etc/systemd/system/afghanvpn-agent.service <<UNIT
[Unit]
Description=AFGHAN VPN node agent
After=network-online.target wg-quick@wg0.service
Requires=wg-quick@wg0.service
[Service]
EnvironmentFile=/etc/afghanvpn/agent.env
ExecStart=/usr/bin/python3 /opt/afghanvpn/agent.py
Restart=always
NoNewPrivileges=true
ProtectHome=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/var/lib/afghanvpn
[Install]
WantedBy=multi-user.target
UNIT

ufw limit OpenSSH
ufw allow 51820/udp
ufw allow from "$BACKEND_IP" to any port 8443 proto tcp
ufw --force enable
systemctl daemon-reload
systemctl enable --now fail2ban
systemctl enable --now wg-quick@wg0
systemctl enable --now afghanvpn-agent

echo
echo "NODE READY (WireGuard + agent running)."
PUBIP=$(ip -4 route get 1.1.1.1 | grep -oP 'src \K\S+' | head -1)
if [ -n "${AUTO_ADD:-}" ] && command -v afghanvpn-admin >/dev/null; then
  IFS='|' read -r SID CTRY CC CITY <<< "$AUTO_ADD"
  sleep 3
  afghanvpn-admin add-server "$SID" "$CTRY" "$CC" "$CITY" "$PUBIP" "$FP" "$SECRET" "$(cat /etc/wireguard/server.pub)" \
    && echo "Server '$SID' registered with your backend. It shows ONLINE within ~30 seconds."
else
  echo "Register this node on your backend with:"
  echo "afghanvpn-admin add-server de-1 Germany DE Frankfurt $PUBIP $FP <secret> $(cat /etc/wireguard/server.pub)"
  echo "(agent_secret is stored in /etc/afghanvpn/agent.env — never share or post it)"
fi
