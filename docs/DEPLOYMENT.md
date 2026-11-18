# AFGHAN VPN — Deployment guide for your Android phone (private GitHub repo)
Costs: nothing until PART E. Do PART E only after you decide to buy the server.
Replace YOURNAME with your GitHub username and myafghanvpn with your DuckDNS name.

## PART A — Private repository (free)
1. Browser: github.com > sign up > **New repository** > name `afghanvpn` > **Private** > Create.
2. Android cannot upload folders, so upload the single file: **Add file > Upload files** > choose `afghan-vpn-phase4.zip` > Commit.
3. **Add file > Create new file**, name it exactly `.github/workflows/unpack.yml`, paste this, Commit:
```
name: Unpack
on: workflow_dispatch
permissions: { contents: write }
jobs:
  unpack:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: |
          unzip -q afghan-vpn-phase4.zip
          rm -rf afghan-vpn/.github
          cp -a afghan-vpn/. .
          rm -rf afghan-vpn afghan-vpn-phase4.zip
          git config user.name unpack; git config user.email unpack@users.noreply.github.com
          git add -A; git commit -m "Add AFGHAN VPN project"; git push
```
4. **Actions** tab > Unpack > Run workflow. After ~30 s the repo shows the folders `app`, `backend`, `server`, `docs`...
5. GitHub cannot let that workflow create workflow files, so do this by hand 3 times: open folder `ci-workflows`, open `build-debug.yml` > copy the text > **Add file > Create new file** `.github/workflows/build-debug.yml` > paste > Commit. Repeat for `build-release.yml` and `create-signing-key.yml`.
6. Every build first runs the secret scanner; if it ever finds a secret, the build stops.
7. **Free compile test (do this now, costs nothing):** Actions > **Build DEBUG APK** > Run. It takes about 6 minutes. This proves whether the app compiles. The APK will open and show your welcome image, but cannot log in yet (no server). **The app has never been compiled before, so a first failure is possible: tap the red run, copy the error text and send it to me.**

## PART B — Free web address
duckdns.org > sign in > create a name such as `myafghanvpn` (leave the IP for later).

## PART C — Signing key for the real app (free, once)
1. Actions > **Create signing key (run ONCE)** > Run. When finished, open the run, download artifact **SIGNING-KEY-PRIVATE-delete-after-use**, unzip.
2. Repo > Settings > Secrets and variables > Actions > **Secrets** > New repository secret, four times:
   `KEYSTORE_B64` = the whole text of keystore.b64.txt · `KEYSTORE_PASSWORD` and `KEY_PASSWORD` = the password in secrets.txt · `KEY_ALIAS` = afghanvpn
3. **Save a private backup of release.jks and secrets.txt** (for example your own private cloud storage). If you lose this key you can never update the app again.
4. Delete the artifact (open the run > the artifact > Delete). Never post these files anywhere.

## PART D — Token so the servers can download from your private repo
GitHub > Settings > Developer settings > Personal access tokens > **Fine-grained** > Generate: repository = only `afghanvpn`, permission **Contents: Read-only**, expiry **7 days**. Copy it somewhere temporary. Delete the token after Part F.

## PART E — Create the server (PAID — wait for your approval)
Provider (see PROVIDERS.md): Ubuntu 24.04, Germany, 2 GB+ RAM. Set a long root password. Note the IP.
In DuckDNS put the IP next to your name > update. Wait 2 minutes. Open the provider's **web console** and log in as root.

## PART F — Install (type in the console)
```
read -rsp "Paste GitHub token (hidden): " T; echo
for f in install-backend.sh install-node.sh; do curl -fsSL -H "Authorization: Bearer $T" -H "Accept: application/vnd.github.raw" "https://api.github.com/repos/YOURNAME/afghanvpn/contents/server/$f" -o $f; done; unset T
DOMAIN=myafghanvpn.duckdns.org bash install-backend.sh
BACKEND_IP=THE.SERVER.IP AUTO_ADD="de-1|Germany|DE|Frankfurt" bash install-node.sh
```
The backend step must end with **401**. Wait 40 s, then `afghanvpn-admin servers` must show `"online":1`.
Create an invite code for each phone: `afghanvpn-admin invite` (one code = one phone, single use).
Then delete the GitHub token in GitHub settings.

## PART G — Build and install the app
1. Repo > Settings > Secrets and variables > Actions > **Variables** > `API_BASE_URL` = `https://myafghanvpn.duckdns.org`
2. Actions > **Build RELEASE APK (signed)** > Run. Wait ~8 minutes for the green tick. (Never run before; if red, send me the error text.)
3. Tap the finished run, scroll to **Artifacts**, tap **AfghanVPN-RELEASE-apk** (Chrome may ask you to sign in to GitHub). A .zip downloads.
4. Files app > Downloads > tap the zip > **Extract** > tap `app-release.apk`.
5. Android asks "Install unknown apps": allow it for the Files app (or Chrome), go back, tap **Install**. Xiaomi security scan / Play Protect may warn: choose **Install anyway** (it is your own app, signed with your key).
6. Open app > CONTINUE > invite code > ACTIVATE > Germany > CONNECT > accept Android's VPN request.
   Success = green PROTECTED + "Verified: your traffic exits via Germany" + "Your public IP" equals the server IP.

## PART H — Kill switch and battery (Redmi, do both)
1. Settings > Connection & sharing > **VPN** > tap the gear next to AFGHAN VPN (it appears after the first connection; the app's "Open VPN settings" button also goes there) > turn on **Always-on VPN** and **Block connections without VPN**. Tick the checkbox in the app.
2. Settings > Apps > Manage apps > AFGHAN VPN > Battery saver: **No restrictions**; turn on **Autostart**.

## PART I — Tests (tell me every result)
- **Welcome screen:** open the app from its icon. The complete image must appear first (both flags, your face, all texts, logo, tagline, nothing cut off) with the green CONTINUE button under it; tap it and it fades into the dashboard. See docs/WELCOME_SCREEN.md.
- Browser "what is my IP": server IP while connected; your real IP after disconnect (with the kill switch on, internet is off after disconnect: normal).
- dnsleaktest.com extended test: only Cloudflare, nothing from your UAE provider.
- test-ipv6.com: no real IPv6 address.
- Kill switch: while connected, Settings > Apps > AFGHAN VPN > Force stop. Internet must stop. Open the app again: it must still load servers.
- Link-lost test: in the server console `systemctl stop wg-quick@wg0`; within about 3 minutes the app must show LINK LOST - TRAFFIC BLOCKED. Then `systemctl start wg-quick@wg0 afghanvpn-agent` and press RECONNECT.
- Switch Wi-Fi <-> mobile data while connected; speed test; note results.

## PART J — Maintenance
Backup: `cp /var/lib/afghanvpn-api/afghanvpn.db /root/backup.db`. Reboot monthly (`reboot`). Revoke a phone: `afghanvpn-admin devices` then `afghanvpn-admin revoke NUMBER`.
Stop paying: delete the server in the provider dashboard.
More countries: run only `install-node.sh` on each new server (no AUTO_ADD), run the printed `afghanvpn-admin add-server ...` line on the backend. Each new server is a new purchase I will ask you about first.

## Troubleshooting
| Problem | Fix |
|---|---|
| Backend step does not print 401 | DuckDNS IP wrong; fix it, then `systemctl restart caddy` |
| Server shows online 0 | `systemctl status afghanvpn-agent`; BACKEND_IP must be the server's own IP |
| Release build fails | Send the red error; check secrets and the API_BASE_URL variable |
| "Safety check failed" | Do not use the VPN; send me the message |
| "Invalid invite code" | Already used or mistyped; make a new one |
