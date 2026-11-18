#!/usr/bin/env python3
"""AFGHAN VPN node agent. Runs on each VPN server. Only the backend may talk to it:
  * TLS (self-signed cert; backend pins its SHA-256 fingerprint)
  * every request signed with HMAC-SHA256 (shared NODE_SECRET), 30 s time window, replay-protected
  * firewall (ufw) additionally allows the port only from the backend IP
It never sees user passwords or private keys: it only receives a phone's PUBLIC key."""
import os, json, ssl, hmac, hashlib, time, re, subprocess, threading, ipaddress
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SECRET = bytes.fromhex(os.environ["NODE_SECRET"])
IFACE = os.environ.get("WG_IFACE", "wg0")
SUBNET = ipaddress.ip_network(os.environ.get("WG_SUBNET", "10.8.0.0/24"))
DNS = os.environ.get("CLIENT_DNS", "1.1.1.1,1.0.0.1")
CAP = int(os.environ.get("CAPACITY", "100"))
TTL = int(os.environ.get("PEER_TTL", "43200"))          # peers auto-expire after 12 h
PORT = int(os.environ.get("AGENT_PORT", "8443"))
STATE = os.environ.get("STATE_FILE", "/var/lib/afghanvpn/peers.json")
CERT = os.environ.get("CERT_FILE", "/etc/afghanvpn/agent.crt")
KEY = os.environ.get("KEY_FILE", "/etc/afghanvpn/agent.key")
KEY_RE = re.compile(r"^[A-Za-z0-9+/]{43}=$")

lock = threading.Lock()
peers = {}   # public_key -> {"ip": "10.8.0.x", "exp": unix_time}
seen = {}    # nonce -> time (replay protection)

def wg(*args):
    subprocess.run(["wg", *args], check=True, capture_output=True, timeout=10)

def save():
    tmp = STATE + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f: json.dump(peers, f)
    os.replace(tmp, STATE)

def restore():
    try: data = json.load(open(STATE))
    except Exception: return
    now = time.time()
    for k, p in data.items():
        if p["exp"] > now and KEY_RE.match(k):
            try: wg("set", IFACE, "peer", k, "allowed-ips", p["ip"] + "/32"); peers[k] = p
            except Exception as e: print("restore failed:", type(e).__name__, flush=True)
    save()

def prune():
    now = time.time()
    for k in [k for k, p in peers.items() if p["exp"] < now]:
        try: wg("set", IFACE, "peer", k, "remove")
        except Exception: pass
        del peers[k]

def alloc_ip():
    used = {p["ip"] for p in peers.values()}
    for h in list(SUBNET.hosts())[1:]:          # .1 is the server itself
        if str(h) not in used: return str(h)
    return None

class H(BaseHTTPRequestHandler):
    timeout = 10
    def setup(self):
        self.request.settimeout(10); self.request.do_handshake()   # handshake in the worker thread, not the accept loop
        super().setup()
    def log_message(self, *a): pass               # never log request details

    def reply(self, code, obj):
        b = json.dumps(obj).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)

    def authed(self, body):
        ts = self.headers.get("X-Timestamp", ""); sig = self.headers.get("X-Signature", ""); nonce = self.headers.get("X-Nonce", "")
        if not re.fullmatch(r"[0-9a-f]{32}", nonce): return False
        if not ts.isdigit() or abs(time.time() - int(ts)) > 30: return False
        exp = hmac.new(SECRET, f"{ts}\n{nonce}\n{self.command}\n{self.path}\n".encode() + body, hashlib.sha256).hexdigest()
        if not hmac.compare_digest(exp, sig): return False
        with lock:
            now = time.time()
            for n in [n for n, t in seen.items() if t < now - 90]: del seen[n]
            if nonce in seen: return False
            seen[nonce] = now
        return True

    def handle_any(self):
        n = int(self.headers.get("Content-Length") or 0)
        if n < 0 or n > 4096: return self.reply(413, {"error": "too large"})
        body = self.rfile.read(n) if n else b""
        if not self.authed(body): return self.reply(401, {"error": "unauthorized"})
        try:
            if self.command == "GET" and self.path == "/status": return self.status()
            if self.command == "POST" and self.path in ("/peer/add", "/peer/remove"):
                key = json.loads(body or b"{}").get("public_key", "")
                if not isinstance(key, str) or not KEY_RE.match(key): return self.reply(400, {"error": "bad key"})
                return self.add(key) if self.path == "/peer/add" else self.remove(key)
            return self.reply(404, {"error": "not found"})
        except Exception as e:
            print("error:", type(e).__name__, flush=True); return self.reply(500, {"error": "internal"})

    do_GET = do_POST = handle_any

    def status(self):
        try: subprocess.run(["wg", "show", IFACE], check=True, capture_output=True, timeout=5)
        except Exception: return self.reply(503, {"error": "wireguard down"})
        with lock:
            prune(); save(); n = len(peers)
        self.reply(200, {"peers": n, "load": min(100, int(100 * n / CAP))})

    def add(self, key):
        with lock:
            prune(); p = peers.get(key)
            if p is None:
                ip = alloc_ip()
                if ip is None or len(peers) >= CAP: return self.reply(409, {"error": "full"})
                wg("set", IFACE, "peer", key, "allowed-ips", ip + "/32")
                p = peers[key] = {"ip": ip, "exp": 0}
            p["exp"] = time.time() + TTL; save()
        self.reply(200, {"address": p["ip"] + "/32", "dns": DNS})

    def remove(self, key):
        with lock:
            if key in peers:
                try: wg("set", IFACE, "peer", key, "remove")
                except Exception: pass
                del peers[key]; save()
        self.reply(200, {"ok": True})

class Srv(ThreadingHTTPServer):
    def handle_error(self, request, client_address): pass   # no tracebacks / client details in logs

def main():
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    restore()
    srv = Srv(("0.0.0.0", PORT), H)
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); ctx.minimum_version = ssl.TLSVersion.TLSv1_2
    ctx.load_cert_chain(CERT, KEY)
    srv.socket = ctx.wrap_socket(srv.socket, server_side=True, do_handshake_on_connect=False)
    srv.serve_forever()

if __name__ == "__main__": main()
