#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
IPA_IN="$ROOT/Discord.ipa"
IPA_OUT="$ROOT/Celeste.ipa"
EXTRACTED="$ROOT/discord-extracted"
DYLIB_NAME="CelestePatch.dylib"
DYLIB_BUILT="$ROOT/CelestePatch/CelestePatch.dylib"

[ -f "$IPA_IN" ] || { echo "missing Discord.ipa"; exit 1; }

export IPHONEOS_SDK="${IPHONEOS_SDK:-$HOME/theos/sdks/iPhoneOS16.5.sdk}"
[ -d "$IPHONEOS_SDK" ] || { echo "missing SDK, run bootstrap.sh"; exit 1; }

INSERT_DYLIB="$ROOT/tools/insert_dylib.py"
[ -x "$INSERT_DYLIB" ] || { echo "missing insert_dylib, run bootstrap.sh"; exit 1; }
command -v ldid >/dev/null || { echo "missing ldid, run bootstrap.sh"; exit 1; }

( cd "$ROOT/CelestePatch" && make clean && IPHONEOS_SDK="$IPHONEOS_SDK" make )
[ -f "$DYLIB_BUILT" ] || { echo "dylib build failed"; exit 1; }
cp "$DYLIB_BUILT" "$ROOT/$DYLIB_NAME"

rm -rf "$EXTRACTED"
mkdir -p "$EXTRACTED"
unzip -q "$IPA_IN" -d "$EXTRACTED"

APP_DIR=$(find "$EXTRACTED/Payload" -maxdepth 1 -type d -name '*.app' | head -1)
[ -n "$APP_DIR" ] || { echo "no .app in Payload"; exit 1; }
BINARY="$APP_DIR/$(basename "$APP_DIR" .app)"
[ -f "$BINARY" ] || { echo "no main binary"; exit 1; }

cp "$ROOT/$DYLIB_NAME" "$APP_DIR/$DYLIB_NAME"
"$INSERT_DYLIB" --strip-codesig --inplace "@executable_path/$DYLIB_NAME" "$BINARY"

rm -rf "$APP_DIR/_CodeSignature" "$APP_DIR/embedded.mobileprovision"
find "$APP_DIR" -name '.DS_Store' -delete 2>/dev/null || true
ldid -S "$BINARY"
ldid -S "$APP_DIR/$DYLIB_NAME"

python3 - "$APP_DIR/Info.plist" <<'PY' || true
import plistlib, sys, pathlib
p = pathlib.Path(sys.argv[1])
with p.open("rb") as f: plist = plistlib.load(f)
plist["CFBundleIdentifier"] = "gg.celeste.app"
plist["CFBundleDisplayName"] = "Celeste"
plist["CFBundleName"] = "Celeste"
plist.pop("CFBundleURLTypes", None)
ats = plist.setdefault("NSAppTransportSecurity", {})
doms = ats.setdefault("NSExceptionDomains", {})
for host in ("celeste.gg","alpha.celeste.gg","alpha-gateway.celeste.gg","cdn.celeste.gg","media.celeste.gg"):
    doms.setdefault(host, {"NSIncludesSubdomains": True, "NSExceptionAllowsInsecureHTTPLoads": False, "NSExceptionRequiresForwardSecrecy": True, "NSExceptionMinimumTLSVersion": "TLSv1.2"})
with p.open("wb") as f: plistlib.dump(plist, f)
PY

for EXT in "$APP_DIR/PlugIns"/*.appex; do
    [ -d "$EXT" ] || continue
    python3 - "$EXT/Info.plist" <<'PY'
import plistlib, sys, pathlib
p = pathlib.Path(sys.argv[1])
with p.open("rb") as f: plist = plistlib.load(f)
bid = plist.get("CFBundleIdentifier", "")
prefix = "com.hammerandchisel.discord."
if bid.startswith(prefix):
    plist["CFBundleIdentifier"] = "gg.celeste.app." + bid[len(prefix):]
    with p.open("wb") as f: plistlib.dump(plist, f)
PY
    rm -rf "$EXT/_CodeSignature" "$EXT/embedded.mobileprovision"
    EXT_BIN="$EXT/$(basename "$EXT" .appex)"
    [ -f "$EXT_BIN" ] && ldid -S "$EXT_BIN"
done

rm -f "$IPA_OUT"
( cd "$EXTRACTED" && zip -qr "$IPA_OUT" Payload )

SIZE=$(stat -c '%s' "$IPA_OUT")
python3 - "$APP_DIR/Info.plist" "$SIZE" <<PY
import plistlib, json, pathlib, sys
plist = plistlib.load(open(sys.argv[1],"rb"))
p = pathlib.Path("$ROOT/source.json")
d = json.loads(p.read_text())
v = d["apps"][0]["versions"][0]
v["size"] = int(sys.argv[2])
v["version"] = plist.get("CFBundleShortVersionString", v["version"])
p.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
PY

echo "built $IPA_OUT ($SIZE bytes)"
