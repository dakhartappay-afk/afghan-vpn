#!/usr/bin/env bash
# Fails (exit 1) if the repository contains something that looks like a secret. Used by every build workflow.
cd "$(dirname "$0")/.."
bad=0
echo "Scanning for secret-looking files..."
if find . -path ./.git -prune -o -type f \( -name '*.jks' -o -name '*.keystore' -o -name '*.p12' -o -name '*.pem' -o -name '*.key' -o -name '.env' -o -name '*.env' -o -name '*.db' -o -name 'peers.json' -o -name 'secrets.txt' -o -name 'keystore.b64.txt' -o -name 'local.properties' \) -print | grep .; then bad=1; fi
echo "Scanning file contents..."
PATTERNS='-----BEGIN [A-Z ]*PRIVATE KEY-----|[0-9a-fA-F]{64}|[A-Za-z0-9+/]{43}=|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|ADMIN_TOKEN=[A-Za-z0-9]{16,}|NODE_SECRET=[0-9a-fA-F]{16,}|(password|passwd|storePassword|keyPassword)[[:space:]]*[=:][[:space:]]*["'"'"'][^"'"'"'$]{4,}'
grep -rIEn --exclude-dir=.git --exclude-dir=build --exclude-dir=.gradle --exclude=scan-secrets.sh --exclude=welcome_art.sha256 -e "$PATTERNS" . ; rc=$?
if [ $rc -eq 0 ]; then bad=1; elif [ $rc -ne 1 ]; then echo "scanner error (grep exit $rc)"; exit 1; fi
[ $bad -eq 0 ] && echo "OK: no secrets found" || { echo "FAILED: remove the lines above before continuing"; exit 1; }
