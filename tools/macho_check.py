#!/usr/bin/env python3
import argparse
import os
import struct
import sys

MH_MAGIC_64 = 0xFEEDFACF
FAT_MAGIC = 0xCAFEBABE
FAT_MAGIC_64 = 0xCAFEBABF
LC_LOAD_DYLIB = 0x0C
LC_LOAD_WEAK_DYLIB = 0x80000018
LC_ENCRYPTION_INFO = 0x21
LC_ENCRYPTION_INFO_64 = 0x2C
LC_CODE_SIGNATURE = 0x1D


def slices(raw):
    magic = struct.unpack_from(">I", raw, 0)[0]
    if magic == FAT_MAGIC:
        n = struct.unpack_from(">I", raw, 4)[0]
        return [struct.unpack_from(">I", raw, 8 + i * 20 + 8)[0] for i in range(n)]
    if magic == FAT_MAGIC_64:
        n = struct.unpack_from(">I", raw, 4)[0]
        return [struct.unpack_from(">Q", raw, 8 + i * 32 + 8)[0] for i in range(n)]
    if struct.unpack_from("<I", raw, 0)[0] == MH_MAGIC_64:
        return [0]
    return []


def inspect(path):
    with open(path, "rb") as f:
        raw = f.read()
    out = []
    for off in slices(raw):
        ncmds = struct.unpack_from("<I", raw, off + 16)[0]
        p = off + 32
        info = {"cryptid": None, "dylibs": [], "signed": False}
        for _ in range(ncmds):
            cmd, size = struct.unpack_from("<II", raw, p)
            if cmd in (LC_ENCRYPTION_INFO, LC_ENCRYPTION_INFO_64):
                info["cryptid"] = struct.unpack_from("<I", raw, p + 16)[0]
            elif cmd in (LC_LOAD_DYLIB, LC_LOAD_WEAK_DYLIB):
                name_off = struct.unpack_from("<I", raw, p + 8)[0]
                info["dylibs"].append(raw[p + name_off : p + size].split(b"\0", 1)[0].decode())
            elif cmd == LC_CODE_SIGNATURE:
                info["signed"] = True
            p += size
        out.append(info)
    return out


def walk_machos(root):
    for d, _, files in os.walk(root):
        for name in files:
            path = os.path.join(d, name)
            if os.path.islink(path):
                continue
            with open(path, "rb") as f:
                head = f.read(4)
            if len(head) == 4 and (struct.unpack(">I", head)[0] in (FAT_MAGIC, FAT_MAGIC_64)
                                   or struct.unpack("<I", head)[0] == MH_MAGIC_64):
                yield path


def main():
    ap = argparse.ArgumentParser(description="check Mach-O files of an extracted .app")
    ap.add_argument("app", help="path to the .app directory")
    ap.add_argument("--require-dylib", help="load command the main binary must carry")
    args = ap.parse_args()

    encrypted = []
    for path in walk_machos(args.app):
        for info in inspect(path):
            if info["cryptid"]:
                encrypted.append(path)
    if encrypted:
        print("[macho_check] FairPlay-encrypted binaries (cryptid != 0), a re-signed app cannot run them:")
        for path in encrypted:
            print("  " + os.path.relpath(path, args.app))
        print("[macho_check] provide a decrypted Discord.ipa")
        return 1

    if args.require_dylib:
        exe = os.path.join(args.app, os.path.basename(args.app.rstrip("/"))[: -len(".app")])
        for info in inspect(exe):
            if args.require_dylib not in info["dylibs"]:
                print(f"[macho_check] {exe} does not load {args.require_dylib}")
                return 1
            if not info["signed"]:
                print(f"[macho_check] {exe} has no code signature")
                return 1
    print("[macho_check] ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
