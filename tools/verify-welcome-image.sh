#!/usr/bin/env bash
# Usage: tools/verify-welcome-image.sh path/to/app.apk
# Fails (exit 1) unless the APK contains your official welcome image unchanged
# (byte-identical, or pixel-identical if Android only re-packed it without changing a single pixel).
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - "$1" <<'PY'
import sys, zipfile, hashlib, io, subprocess
apk = sys.argv[1]
orig = open("app/src/main/res/drawable-nodpi/welcome_art.png", "rb").read()
want = hashlib.sha256(orig).hexdigest()
z = zipfile.ZipFile(apk)
pngs = [n for n in z.namelist() if n.lower().endswith(".png") and n.startswith("res/")]
for n in pngs:
    if hashlib.sha256(z.read(n)).hexdigest() == want:
        print("OK: byte-identical copy of your welcome image is inside the APK:", n); sys.exit(0)
try: from PIL import Image
except ImportError:
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "--break-system-packages", "pillow"])
    from PIL import Image
ref = Image.open(io.BytesIO(orig)).convert("RGBA")
for n in pngs:
    try: im = Image.open(io.BytesIO(z.read(n))).convert("RGBA")
    except Exception: continue
    if im.size == ref.size and im.tobytes() == ref.tobytes():
        print("OK: pixel-identical copy of your welcome image is inside the APK:", n); sys.exit(0)
print("FAILED: your welcome image is missing from the APK or was altered."); sys.exit(1)
PY
