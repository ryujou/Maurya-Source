#!/usr/bin/env python3
"""Build deterministic Maurya core and fixed-image resource packs."""

from __future__ import annotations

import argparse
import hashlib
import struct
from pathlib import Path

MAGIC = b"MRPK"
VERSION = 1
HEADER = struct.Struct("<4sHHI32s")
RECORD = struct.Struct("<HII32s")


def collect(root: Path, include_images: bool) -> list[tuple[str, Path]]:
    result: list[tuple[str, Path]] = []
    for path in sorted(root.rglob("*"), key=lambda item: item.as_posix()):
        if not path.is_file():
            continue
        rel = path.relative_to(root).as_posix()
        is_image = rel.startswith("avatars/") or rel.startswith("group-icons/")
        if is_image == include_images:
            result.append(("/" + rel.removesuffix(".gz"), path))
    return result


def build_pack(entries: list[tuple[str, Path]], output: Path) -> None:
    records: list[tuple[bytes, bytes, bytes]] = []
    table_size = 0
    for uri, path in entries:
        uri_bytes = uri.encode("utf-8")
        payload = path.read_bytes()
        digest = hashlib.sha256(payload).digest()
        records.append((uri_bytes, payload, digest))
        table_size += RECORD.size + len(uri_bytes)

    data_offset = HEADER.size + table_size
    table = bytearray()
    data = bytearray()
    for uri, payload, digest in records:
        table += RECORD.pack(len(uri), data_offset + len(data), len(payload), digest)
        table += uri
        data += payload

    body = bytes(table + data)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(
        HEADER.pack(MAGIC, VERSION, len(records), data_offset, hashlib.sha256(body).digest())
        + body
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--web-root", type=Path, required=True)
    parser.add_argument("--assets-pack", type=Path, required=True)
    parser.add_argument("--core-pack", type=Path, required=True)
    args = parser.parse_args()

    build_pack(collect(args.web_root, include_images=True), args.assets_pack)
    build_pack(collect(args.web_root, include_images=False), args.core_pack)

    assets_size = args.assets_pack.stat().st_size
    if assets_size > int(0x1C0000 * 0.90):
        raise SystemExit(f"assets.pack exceeds 90% gate: {assets_size} bytes")
    print(f"assets.pack={assets_size} bytes core.pack={args.core_pack.stat().st_size} bytes")


if __name__ == "__main__":
    main()
