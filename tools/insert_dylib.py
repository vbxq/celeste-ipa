#!/usr/bin/env python3
import argparse
import os
import struct
import sys

MH_MAGIC_64  = 0xFEEDFACF
MH_CIGAM_64  = 0xCFFAEDFE
FAT_MAGIC    = 0xCAFEBABE
FAT_MAGIC_64 = 0xCAFEBABF

LC_LOAD_DYLIB     = 0x0C
LC_CODE_SIGNATURE = 0x1D
LC_SEGMENT_64     = 0x19


def _pad(n, a=8):
    return (n + a - 1) & ~(a - 1)


def _patch(data: bytearray, offset: int, dylib: bytes, strip_sig: bool) -> None:
    magic = struct.unpack_from("<I", data, offset)[0]
    if magic != MH_MAGIC_64:
        raise SystemExit(
            f"[insert_dylib] magic inattendu 0x{magic:08x} à l'offset 0x{offset:x}"
        )

    hdr = struct.unpack_from("<IIIIIIII", data, offset)
    _, cputype, cpusub, filetype, ncmds, sizeofcmds, flags, reserved = hdr
    cmds_start = offset + 32

    if strip_sig:
        p = cmds_start
        kept = bytearray()
        new_ncmds = 0
        for _ in range(ncmds):
            cmd, cmdsize = struct.unpack_from("<II", data, p)
            if cmd != LC_CODE_SIGNATURE:
                kept += bytes(data[p : p + cmdsize])
                new_ncmds += 1
            p += cmdsize
        pad = sizeofcmds - len(kept)
        data[cmds_start : cmds_start + sizeofcmds] = kept + b"\x00" * pad
        struct.pack_into("<II", data, offset + 16, new_ncmds, len(kept))
        ncmds, sizeofcmds = new_ncmds, len(kept)

    # détermine le padding disponible après les load commands : c'est la zone entre (cmds_start + sizeofcmds) et le plus petit fileoff
    # d'un segment/section __TEXT.__text.
    # on cherche le plus petit non-zéro parmi les fileoff LC_SEGMENT_64
    first_section_offset = None
    p = cmds_start
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, p)
        if cmd == LC_SEGMENT_64:
            # segment_command_64 : cmd(4) cmdsize(4) segname(16) vmaddr(8)
            # vmsize(8) fileoff(8) filesize(8) maxprot(4) initprot(4)
            # nsects(4) flags(4)
            fileoff = struct.unpack_from("<Q", data, p + 32)[0]
            if fileoff > 0:
                first_section_offset = (
                    fileoff
                    if first_section_offset is None
                    else min(first_section_offset, fileoff)
                )
        p += cmdsize

    if first_section_offset is None:
        first_section_offset = len(data)

    free = first_section_offset - (cmds_start + sizeofcmds)

    # nouvelle commande LC_LOAD_DYLIB
    name = dylib + b"\x00"
    name_struct_size = 24  # cmd(4) cmdsize(4) name.offset(4) ts(4) cur(4) compat(4)
    cmdsize = _pad(name_struct_size + len(name), 8)
    lc = struct.pack(
        "<IIIIII",
        LC_LOAD_DYLIB,
        cmdsize,
        name_struct_size,  # offset du champ name depuis le début de la cmd
        2,                 # timestamp
        0x00010000,        # current_version 1.0.0
        0x00010000,        # compatibility_version 1.0.0
    ) + name + b"\x00" * (cmdsize - (name_struct_size + len(name)))

    if len(lc) > free:
        raise SystemExit(
            f"[insert_dylib] padding insuffisant à l'offset 0x{offset:x}: "
            f"{free} dispos, {len(lc)} requis"
        )

    ins_at = cmds_start + sizeofcmds
    data[ins_at : ins_at + cmdsize] = lc
    struct.pack_into("<II", data, offset + 16, ncmds + 1, sizeofcmds + cmdsize)


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Injecte un LC_LOAD_DYLIB dans un binaire Mach-O"
    )
    ap.add_argument("--strip-codesig", action="store_true",
                    help="retire LC_CODE_SIGNATURE (nécessaire avant ldid -S)")
    ap.add_argument("--inplace", action="store_true",
                    help="écrase le binaire au lieu d'écrire <binary>_patched")
    ap.add_argument("dylib", help="chemin @rpath/xxx.dylib à ajouter")
    ap.add_argument("binary", help="Mach-O cible")
    args = ap.parse_args()

    with open(args.binary, "rb") as f:
        raw = bytearray(f.read())

    magic = struct.unpack_from(">I", raw, 0)[0]
    if magic == FAT_MAGIC:
        nfat = struct.unpack_from(">I", raw, 4)[0]
        for i in range(nfat):
            fileoff = struct.unpack_from(">I", raw, 8 + i * 20 + 8)[0]
            _patch(raw, fileoff, args.dylib.encode(), args.strip_codesig)
    elif magic == FAT_MAGIC_64:
        nfat = struct.unpack_from(">I", raw, 4)[0]
        for i in range(nfat):
            fileoff = struct.unpack_from(">Q", raw, 8 + i * 32 + 8)[0]
            _patch(raw, fileoff, args.dylib.encode(), args.strip_codesig)
    else:
        _patch(raw, 0, args.dylib.encode(), args.strip_codesig)

    out_path = args.binary if args.inplace else args.binary + "_patched"
    with open(out_path, "wb") as f:
        f.write(raw)
    os.chmod(out_path, 0o755)
    print(f"[insert_dylib] patched {out_path} ({len(raw)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
