# AFGHAN VPN — Architecture (Phase 3)
Phone app -> HTTPS -> Backend -> (pinned TLS + HMAC) -> Node agent on each VPN server -> WireGuard (wg0).

## Connect flow
1. Phone makes a WireGuard key pair. Private key stays in memory only; the PUBLIC key goes to /v1/connect.
2. Backend checks the device token, picks the server (must be online), asks its node agent to add the public key as a peer.
3. Agent gives the phone a tunnel IP (10.8.0.x/32) and DNS. Backend returns that + server public key + endpoint.
4. App starts the WireGuard tunnel, then asks /v1/whoami THROUGH the tunnel. The backend must see the chosen VPN server
   (not the phone's real IP). If not, the app disconnects and shows an error. It never shows "protected" without this check.
5. Disconnect: tunnel down, then /v1/disconnect removes the peer. Peers also auto-expire after 12 h.

## Security
- Devices: invite code (single use) -> private token (only its hash stored; app keeps it in Android Keystore-encrypted storage).
- Admin API: ADMIN_TOKEN (32+ chars), constant-time check, rate limited. Never returns node secrets.
- Node agent: TLS with pinned fingerprint, HMAC-signed requests (30 s window + nonce replay cache), firewall allows only the backend IP.
- Agent never receives private keys or user identities. No traffic or browsing logs are kept.

## Status (honest)
TESTED here: agent protocol (signing, replay block, fingerprint pin, bad key, full server, idempotent add/remove) with a stubbed `wg`.
NOT TESTED: real WireGuard traffic, backend with FastAPI installed, Android build, any real server. These need real servers/phone.
NOT DONE: user accounts/payments, admin web UI, ping display, split tunneling, auto-reconnect, OpenVPN, IPv6 server-side, release signing,
app icon, own DNS resolver (currently 1.1.1.1), independent security audit.
Known limits: IP check proves traffic exits via YOUR server, not that the country label is right (that depends on the hosting location).
Kill switch: Android Settings > VPN > Always-on VPN + "Block connections without VPN".
