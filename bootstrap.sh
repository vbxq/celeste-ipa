#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$ROOT/tools"
LOCAL_BIN="${LOCAL_BIN:-$HOME/.local/bin}"
mkdir -p "$LOCAL_BIN"

need() { command -v "$1" >/dev/null || { echo "missing $1"; exit 1; }; }
need clang
need lld
need git
need make
need python3
need unzip
need zip

SDK_DIR="${IPHONEOS_SDK:-$HOME/theos/sdks/iPhoneOS16.5.sdk}"
if [ ! -d "$SDK_DIR" ]; then
  mkdir -p "$(dirname "$SDK_DIR")"
  TMP="$(mktemp -d)"
  git clone --depth 1 --filter=blob:none --sparse https://github.com/theos/sdks.git "$TMP"
  ( cd "$TMP" && git sparse-checkout set iPhoneOS16.5.sdk )
  mv "$TMP/iPhoneOS16.5.sdk" "$SDK_DIR"
  rm -rf "$TMP"
fi

if ! command -v ldid >/dev/null && [ ! -x "$LOCAL_BIN/ldid" ]; then
  [ -d "$ROOT/tools/ldid" ] || git clone --depth 1 https://github.com/ProcursusTeam/ldid.git "$ROOT/tools/ldid"
  ( cd "$ROOT/tools/ldid" && make )
  install -m 0755 "$ROOT/tools/ldid/ldid" "$LOCAL_BIN/ldid"
fi

chmod +x "$ROOT/tools/insert_dylib.py"
