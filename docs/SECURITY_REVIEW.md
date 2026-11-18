# AFGHAN VPN — Security review (final, Phase 4)
Done by the developer/AI. **This is NOT an independent security audit.** Nothing here was tested on real WireGuard traffic, a real server, or your phone.

## 1. Questions you asked
| Question | Answer |
|---|---|
| Do private keys leave the phone? | No. The private key is created in the app, goes only to the WireGuard library, and is never sent, stored or logged (checked by searching all code). Only the PUBLIC key goes to the server. App backup is off. |
| Can unauthorized people control a server? | Node agent: firewall allows only the backend IP + pinned TLS identity + signed, replay-protected requests. Admin API: 64-hex-char token, rate limited, never returns secrets. A phone can only manage its own connection. Unknown/revoked devices get 401. |
| Secrets in the repository? | None found. `tools/scan-secrets.sh` checks for private keys, 64-hex secrets, WireGuard-style keys, GitHub tokens, passwords, keystores, .env, databases. It runs before every build. I tested it by planting 6 fake secrets: all were caught. Real secrets live only in GitHub Secrets / on the servers. |
| Can the repo stay private? | Yes. See DEPLOYMENT.md (servers download with a short-lived read-only token). |

## 2. Fixed in this review (all phases)
Users could reach each other / provider network (firewalled) · outgoing spam port 25 (blocked) · database locked during slow calls · stalled TLS handshake could freeze agent ·
unbounded rate-limit memory · connect spam (10/min/device) · access logs disabled · admin token never printed · backend not root · DB chmod 600 ·
**new:** rate limit is now per device (many VPN users share one server IP, a per-IP limit would block real users) with a strict failed-login limit per IP ·
request bodies limited to 10 KB · SSH rate-limited + fail2ban + automatic security updates · app refuses non-HTTPS backend ·
app refuses DNS settings that are not plain IP addresses (a hostname would be looked up outside the tunnel = leak) · two DNS servers for reliability.

## 3. Kill switch (honest description)
- **Layer 1 — built into the app:** while connected, ALL IPv4 and IPv6 traffic is forced into the tunnel. If the server or network dies, traffic is dropped, not leaked.
  The app watches the WireGuard handshake; if it is older than 3 minutes it shows **LINK LOST - TRAFFIC BLOCKED** and a RECONNECT button. (Untested on a real phone; a phone in deep sleep may show it briefly after waking.)
- **Layer 2 — Android's own setting (you must switch it on):** *Always-on VPN* + *Block connections without VPN*. It covers: app crash/killed by Android, before connecting, reboot.
  **No app can switch this on by itself** (Android allows it only for company-managed phones). The app opens the settings page and has a checkbox to remember that you did it; the app CANNOT verify it, so it says "set by you".
- Not yet verified: with this setting on, the app's own server calls must still work (Android normally exempts the VPN app itself). If not, tell me.
- With the setting on, pressing DISCONNECT turns the internet off until you connect again. That is the intended behaviour.
- Xiaomi/Redmi may kill background apps: set AFGHAN VPN to "No restrictions" for battery and enable Autostart.

## 4. DNS leak review
- DNS servers (1.1.1.1 and 1.0.0.1, Cloudflare) are set inside the tunnel, so DNS questions travel through the tunnel and your UAE provider does not see them. They leave from the VPN server.
- IPv6: all IPv6 is routed into the tunnel and dropped by the server, so no IPv6 leak (some IPv6-only websites will not open).
- Phone "Private DNS" setting: its queries also go through the tunnel, so no leak, but it may bypass our DNS choice.
- Apps that ignore system DNS (their own DNS-over-HTTPS) still go through the tunnel.
- Privacy limit: Cloudflare can see which domain names are looked up (from the server IP, not your identity). A private DNS resolver on each server is a later upgrade.
- **You must run the DNS leak test on your phone** (DEPLOYMENT.md step 9). I could not.

## 5. Production Android build — status
Prepared: release build with code shrinking (R8), not debuggable, signed with YOUR key from GitHub Secrets, refuses to build with a placeholder URL or without the key, HTTPS-only network config.
**Never compiled yet.** The first build may fail or R8 may remove something it should not; send me the error. Not for Google Play yet (needs store listing, privacy policy, review).
The debug APK is for your own testing only (debuggable).

## 6. Known limits (not fixed)
- Backend and node share one server in the first test: if it is hacked, both are. Production should separate them.
- Device tokens never expire (revocable). Admin API is reachable from the internet (token + rate limit).
- Node secret is stored on the node and in the backend database.
- Country label depends on the provider's real location; the app proves "exits via your server", not the country.
- Not built: accounts/payments, admin web page, ping display, split tunneling, auto-reconnect, OpenVPN, own DNS, auto-update, app icon.
- Legal: UAE restricts VPN use. Check the law before selling or sharing the app.

## 7. Tests that passed (stand-in WireGuard, real agent + backend code)
Agent: wrong secret, replay, wrong certificate fingerprint, bad key, full server, repeat add, remove, negative Content-Length.
Backend: admin with no/wrong/right token; invite reuse; bad invite; fake/no token; revoked device; offline server (503); bad key (400); unknown server (404); whoami inside/outside tunnel;
register brute-force (429 after 5); bad-token brute-force (429 after 30); DB file permissions 600; no secrets in admin list.
Secret scanner: clean repo passes, 6 planted secrets caught.
NOT tested: Android app (never compiled), real WireGuard traffic, installers on a real Ubuntu server, kill switch, DNS/IPv6 leak, speed.

## 8. Final review round (every file re-read) — what was found
| # | Severity | Problem | Status |
|---|----------|---------|--------|
| 1 | HIGH (honesty) | If you left the app with the Back button while connected, reopening it showed "NOT CONNECTED" although the VPN was still running (the tunnel lives in a system service). Reconnecting could also create a second tunnel. | FIXED: one app-wide VPN controller; the screen re-reads the true state on opening |
| 2 | HIGH (honesty) | If Android or another VPN app switched our VPN off, the app kept saying PROTECTED | FIXED: the app watches the tunnel and shows "VPN was turned off... NOT protected" |
| 3 | MEDIUM | Failed disconnect still showed "disconnected" | FIXED: if shutdown fails the app says so and keeps showing connected |
| 4 | MEDIUM | App data could be copied by Android backup/transfer; restored encrypted data could crash the app | FIXED: backup and device-transfer excluded; storage resets itself instead of crashing |
| 5 | MEDIUM | Server list could shrink to nothing on small screens (kill-switch rows added) | FIXED: list gets the remaining space |
| 6 | MEDIUM | "Open VPN settings" could crash on phones without that screen | FIXED: falls back to normal Settings |
| 7 | LOW | Invite codes never expired | FIXED: valid 14 days |
| 8 | LOW | Agent could wait 10 s on a negative Content-Length before login check | FIXED (tested: refused instantly) |
| 9 | LOW | Backend files created with default permissions | FIXED: umask 077 |
| 10 | LOW | Build workflows had default (write) token rights; no time limit | FIXED: read-only token, 30 min limit; keytool errors now visible |
Checked and found OK: SQL queries (all parameterised), admin/device authentication, constant-time comparisons, replay protection, WireGuard config (allowed IPs, keepalive, MTU default),
private key never leaves the phone, installer scripts (permissions, firewall order, service hardening), YAML of all workflows (parsed OK), private-repo download method, secret scanner.

## 9. REMAINING problems (not fixed — be aware)
1. **The Android app has never been compiled or run.** I can only check syntax by reading; the first GitHub build may fail. Nothing about the app is proven to work on a phone yet.
2. Kill switch layer 2 is Android's setting that YOU must turn on; the app cannot check it. Not verified that the app's own calls work while it is on.
3. Android's own system connectivity checks (and Xiaomi system services) may still contact the internet outside the tunnel. This cannot be controlled by an app.
4. No certificate pinning for the backend (it trusts Android's normal certificate list).
5. GitHub Actions are pinned to version numbers, not exact commit codes (supply-chain risk is small but real).
6. The VPN private key exists as a text string in phone memory while connected (cannot be erased on demand in Android's runtime).
7. Backend + node on one server in the test; one backend is a single point of failure; backend/agent secrets are readable by root on those servers.
8. Release build uses code shrinking (R8) which can break things in ways only a real run shows.
9. Not built: accounts/payments, admin web page, ping, split tunneling, auto-reconnect, OpenVPN, own DNS, auto-update, app icon, Play Store readiness, independent security audit.
10. Test gap: the test line "register spam" in my test file reports FAIL because it stops at the first (expected) 403; the brute-force limit itself was tested separately (5 tries allowed, then 429).
