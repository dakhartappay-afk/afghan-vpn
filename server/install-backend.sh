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
"""AFGHAN VPN backend.
Run: ADMIN_TOKEN=<32+ random chars> uvicorn main:app --proxy-headers --forwarded-allow-ips=127.0.0.1 (behind HTTPS reverse proxy)
Security: devices need an invite code -> private device token (only its hash is stored); admin API needs ADMIN_TOKEN;
node agents are reached over pinned TLS + HMAC; per-IP rate limits. Keep the DB file private (chmod 600)."""
import os, re, json, ssl, time, hmac, socket, sqlite3, secrets, hashlib, asyncio, threading, http.client
from collections import defaultdict, deque
from contextlib import asynccontextmanager, contextmanager
from fastapi import FastAPI, Header, HTTPException, Request, Depends
from pydantic import BaseModel

os.umask(0o077)                      # every file this program creates is private to its user
DB = os.environ.get("DB_PATH", "afghanvpn.db")
ADMIN = os.environ.get("ADMIN_TOKEN", "")
KEY_RE = re.compile(r"^[A-Za-z0-9+/]{43}=$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
sha = lambda s: hashlib.sha256(s.encode()).hexdigest()

@contextmanager
def conn():
    new = not os.path.exists(DB)
    c = sqlite3.connect(DB, timeout=10); c.row_factory = sqlite3.Row
    if new: os.chmod(DB, 0o600); c.execute("PRAGMA journal_mode=WAL")
    c.executescript("""
    CREATE TABLE IF NOT EXISTS servers(id TEXT PRIMARY KEY, country TEXT, code TEXT, city TEXT, host TEXT, ip TEXT,
      agent_port INT, agent_fp TEXT, agent_secret TEXT, wg_public_key TEXT, wg_port INT, capacity INT,
      load INT DEFAULT 0, online INT DEFAULT 0, enabled INT DEFAULT 1, checked REAL DEFAULT 0);
    CREATE TABLE IF NOT EXISTS invites(code_hash TEXT PRIMARY KEY, used INT DEFAULT 0, created REAL);
    CREATE TABLE IF NOT EXISTS devices(id INTEGER PRIMARY KEY, token_hash TEXT UNIQUE, revoked INT DEFAULT 0, created REAL);
    CREATE TABLE IF NOT EXISTS sessions(device_id INT, server_id TEXT, public_key TEXT, address TEXT, created REAL);""")
    try:
        yield c; c.commit()
    finally:
        c.close()

# ---- rate limiting (per client IP) ----
_hits = defaultdict(deque); _lk = threading.Lock()
def limit(ip, bucket, n, per=60):
    now = time.time()
    with _lk:
        q = _hits[(ip, bucket)]
        while q and q[0] < now - per: q.popleft()
        if len(q) >= n: raise HTTPException(429, "Too many requests. Please wait a moment.")
        q.append(now)

def cleanup_limits():
    now = time.time()
    with _lk:
        for k in [k for k, q in _hits.items() if not q or q[-1] < now - 120]: del _hits[k]

# ---- auth ----
def admin(request: Request, x_admin_token: str = Header(None)):
    limit(request.client.host, "admin", 20)
    if len(ADMIN) < 32 or not x_admin_token or not hmac.compare_digest(sha(x_admin_token), sha(ADMIN)):
        raise HTTPException(401, "Unauthorized")

def device(request: Request, authorization: str = Header(None)):
    ip = request.client.host
    limit(ip, "coarse", 3000)                     # very high ceiling per IP (many VPN users share one IP)
    if not authorization or not authorization.startswith("Bearer "):
        limit(ip, "authfail", 30); raise HTTPException(401, "Please activate with an invite code")
    h = sha(authorization[7:])
    limit(h[:16], "api", 120)                     # normal limit is per device token
    with conn() as c:
        r = c.execute("SELECT id FROM devices WHERE token_hash=? AND revoked=0", (h,)).fetchone()
    if not r:
        limit(ip, "authfail", 30); raise HTTPException(401, "This device is not authorized. Please activate again.")
    return r["id"]

# ---- node agent client: pinned TLS + HMAC ----
class AgentError(Exception):
    def __init__(self, msg, status=0): super().__init__(msg); self.status = status

def agent_call(s, method, path, body=None, timeout=8):
    raw = json.dumps(body or {}).encode() if method == "POST" else b""
    ts = str(int(time.time())); nonce = secrets.token_hex(16)
    sig = hmac.new(bytes.fromhex(s["agent_secret"]), f"{ts}\n{nonce}\n{method}\n{path}\n".encode() + raw, hashlib.sha256).hexdigest()
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT); ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE
    ctx.minimum_version = ssl.TLSVersion.TLSv1_2
    cn = http.client.HTTPSConnection(s["host"], s["agent_port"], timeout=timeout, context=ctx)
    try:
        cn.connect()
        if not hmac.compare_digest(hashlib.sha256(cn.sock.getpeercert(binary_form=True)).hexdigest(), s["agent_fp"]):
            raise AgentError("server identity mismatch")
        cn.request(method, path, body=raw if method == "POST" else None,
                   headers={"X-Timestamp": ts, "X-Nonce": nonce, "X-Signature": sig, "Content-Type": "application/json"})
        r = cn.getresponse(); data = r.read(65536)
        if r.status != 200: raise AgentError(f"agent status {r.status}", r.status)
        return json.loads(data)
    except AgentError: raise
    except Exception as e: raise AgentError(type(e).__name__) from e
    finally: cn.close()

def check_all():
    with conn() as c:
        rows = c.execute("SELECT * FROM servers WHERE enabled=1").fetchall()
        c.execute("DELETE FROM sessions WHERE created < ?", (time.time() - 13 * 3600,))
    results = []                      # network calls happen with NO database lock held
    for s in rows:
        try: results.append((1, agent_call(s, "GET", "/status", timeout=5).get("load", 0), s["id"]))
        except AgentError: results.append((0, s["load"], s["id"]))
    with conn() as c:
        for on, load, sid in results:
            c.execute("UPDATE servers SET online=?, load=?, checked=? WHERE id=?", (on, load, time.time(), sid))
    cleanup_limits()

async def health_loop():
    while True:
        try: await asyncio.to_thread(check_all)
        except Exception: pass
        await asyncio.sleep(30)

@asynccontextmanager
async def lifespan(app):
    t = asyncio.create_task(health_loop()); yield; t.cancel()

app = FastAPI(title="AFGHAN VPN API", lifespan=lifespan, docs_url=None, redoc_url=None, openapi_url=None)

# ---- models ----
class Register(BaseModel): code: str
class ConnectReq(BaseModel): server_id: str; public_key: str
class KeyReq(BaseModel): public_key: str
class NewServer(BaseModel):
    id: str; country: str; code: str; city: str; host: str
    agent_fp: str; agent_secret: str; wg_public_key: str
    agent_port: int = 8443; wg_port: int = 51820; capacity: int = 100

# ---- device API ----
@app.post("/v1/register")
def register(r: Register, request: Request):
    limit(request.client.host, "register", 5)
    code = r.code.strip().upper()
    with conn() as c:
        cur = c.execute("UPDATE invites SET used=1 WHERE code_hash=? AND used=0 AND created > ?", (sha(code), time.time() - 14 * 86400))
        if cur.rowcount != 1: raise HTTPException(403, "Invalid, expired or already used invite code")
        token = secrets.token_urlsafe(32)
        c.execute("INSERT INTO devices(token_hash, created) VALUES(?,?)", (sha(token), time.time()))
    return {"token": token}

@app.get("/v1/servers")
def servers(_=Depends(device)):
    with conn() as c:
        rows = c.execute("SELECT id,country,code,city,load,online FROM servers WHERE enabled=1 ORDER BY country").fetchall()
    return [dict(r, online=bool(r["online"])) for r in rows]

def _end_sessions(dev, key=None):
    """Remove the device's peer(s) on the nodes (network, no DB lock held), then forget the sessions."""
    q = "SELECT * FROM sessions WHERE device_id=?" + (" AND public_key=?" if key else "")
    with conn() as c:
        sess = c.execute(q, (dev, key) if key else (dev,)).fetchall()
        srv = {r["id"]: r for r in c.execute("SELECT * FROM servers").fetchall()}
    for ss in sess:
        s = srv.get(ss["server_id"])
        if s:
            try: agent_call(s, "POST", "/peer/remove", {"public_key": ss["public_key"]})
            except AgentError: pass          # the agent also auto-expires peers
    with conn() as c:
        for ss in sess: c.execute("DELETE FROM sessions WHERE device_id=? AND public_key=?", (dev, ss["public_key"]))

UNAVAILABLE = "This server is currently unavailable. Please choose another location."

@app.post("/v1/connect")
def connect(r: ConnectReq, dev=Depends(device)):
    limit(f"device{dev}", "connect", 10)
    if not KEY_RE.match(r.public_key): raise HTTPException(400, "Invalid key")
    with conn() as c: s = c.execute("SELECT * FROM servers WHERE id=? AND enabled=1", (r.server_id,)).fetchone()
    if not s: raise HTTPException(404, "Unknown server")
    if not s["online"]: raise HTTPException(503, UNAVAILABLE)
    _end_sessions(dev)                       # one active session per device
    try: res = agent_call(s, "POST", "/peer/add", {"public_key": r.public_key})
    except AgentError as e:
        if e.status == 409: raise HTTPException(503, "This server is full. Please choose another location.")
        with conn() as c: c.execute("UPDATE servers SET online=0 WHERE id=?", (s["id"],))
        raise HTTPException(503, UNAVAILABLE)
    with conn() as c: c.execute("INSERT INTO sessions VALUES(?,?,?,?,?)", (dev, s["id"], r.public_key, res["address"], time.time()))
    return {"address": res["address"], "dns": res["dns"], "server_public_key": s["wg_public_key"],
            "endpoint": f'{s["host"]}:{s["wg_port"]}'}

@app.post("/v1/disconnect")
def disconnect(r: KeyReq, dev=Depends(device)):
    if not KEY_RE.match(r.public_key): raise HTTPException(400, "Invalid key")
    _end_sessions(dev, r.public_key)
    return {"ok": True}

@app.get("/v1/whoami")
def whoami(request: Request, dev=Depends(device)):
    """Tells the app which IP this request came from, and which of OUR servers that IP belongs to."""
    ip = request.client.host
    with conn() as c:
        ss = c.execute("SELECT server_id FROM sessions WHERE device_id=? AND address LIKE ?", (dev, ip + "/%")).fetchone()
        sv = c.execute("SELECT id FROM servers WHERE ip=?", (ip,)).fetchone()
    return {"ip": ip, "server_id": ss["server_id"] if ss else (sv["id"] if sv else None)}

# ---- admin API ----
@app.post("/admin/servers")
def add_server(s: NewServer, _=Depends(admin)):
    if not (HEX64.match(s.agent_fp) and HEX64.match(s.agent_secret) and KEY_RE.match(s.wg_public_key)):
        raise HTTPException(400, "agent_fp / agent_secret / wg_public_key look wrong")
    try: ip = socket.gethostbyname(s.host)
    except OSError: raise HTTPException(400, "Cannot resolve host")
    with conn() as c:
        c.execute("INSERT OR REPLACE INTO servers(id,country,code,city,host,ip,agent_port,agent_fp,agent_secret,wg_public_key,wg_port,capacity) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)",
                  (s.id, s.country, s.code.upper(), s.city, s.host, ip, s.agent_port, s.agent_fp, s.agent_secret, s.wg_public_key, s.wg_port, s.capacity))
    return {"ok": True}

@app.get("/admin/servers")
def list_servers(_=Depends(admin)):
    with conn() as c:   # secrets are never returned
        return [dict(r) for r in c.execute("SELECT id,country,code,city,host,load,online,enabled,capacity,checked FROM servers")]

@app.delete("/admin/servers/{sid}")
def del_server(sid: str, _=Depends(admin)):
    with conn() as c: c.execute("DELETE FROM servers WHERE id=?", (sid,))
    return {"ok": True}

@app.post("/admin/servers/{sid}/enabled/{flag}")
def enable(sid: str, flag: int, _=Depends(admin)):
    with conn() as c: c.execute("UPDATE servers SET enabled=? WHERE id=?", (1 if flag else 0, sid))
    return {"ok": True}

@app.post("/admin/invites")
def new_invite(_=Depends(admin)):
    h = secrets.token_hex(6).upper(); code = f"AFG-{h[:6]}-{h[6:]}"
    with conn() as c: c.execute("INSERT INTO invites(code_hash, created) VALUES(?,?)", (sha(code), time.time()))
    return {"code": code}          # shown once; only its hash is stored

@app.get("/admin/devices")
def list_devices(_=Depends(admin)):
    with conn() as c: return [dict(r) for r in c.execute("SELECT id,revoked,created FROM devices")]

@app.post("/admin/devices/{did}/revoke")
def revoke(did: int, _=Depends(admin)):
    with conn() as c: c.execute("UPDATE devices SET revoked=1 WHERE id=?", (did,))
    return {"ok": True}
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
