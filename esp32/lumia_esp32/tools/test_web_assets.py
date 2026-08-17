from __future__ import annotations

import argparse
import gzip
import json
import re
import struct
from pathlib import Path


def webp_size(payload: bytes) -> tuple[int, int]:
    assert payload[:4] == b"RIFF" and payload[8:12] == b"WEBP"
    chunk = payload[12:16]
    if chunk == b"VP8X":
        return (
            1 + int.from_bytes(payload[24:27], "little"),
            1 + int.from_bytes(payload[27:30], "little"),
        )
    if chunk == b"VP8L":
        bits = struct.unpack_from("<I", payload, 21)[0]
        return 1 + (bits & 0x3FFF), 1 + ((bits >> 14) & 0x3FFF)
    if chunk == b"VP8 ":
        return (
            struct.unpack_from("<H", payload, 26)[0] & 0x3FFF,
            struct.unpack_from("<H", payload, 28)[0] & 0x3FFF,
        )
    raise AssertionError(f"unsupported WebP chunk {chunk!r}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--variant", choices=("multilingual", "ja"), default="multilingual")
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[1]
    web = project / "web"
    gzip_files = sorted(web.rglob("*.gz"))
    webp_files = sorted(web.rglob("*.webp"))

    assert len(webp_files) == 536
    assert len(list((web / "avatars").glob("*.webp"))) == 505
    assert len(list((web / "group-icons").glob("*.webp"))) == 31
    for path in gzip_files:
        compressed = path.read_bytes()
        assert compressed[4:8] == b"\0\0\0\0", f"{path.name} gzip mtime"
        assert gzip.decompress(compressed), f"{path.name} is empty"
    avatar_files = sorted((web / "avatars").glob("*.webp"))
    assert all(webp_size(path.read_bytes()) == (96, 96) for path in avatar_files)
    assert sum(path.stat().st_size for path in avatar_files) <= 1_650_000

    html = gzip.decompress((web / "index.html.gz").read_bytes()).decode("utf-8")
    palette = json.loads(gzip.decompress((web / "palette.json.gz").read_bytes()))
    javascript = "\n".join(
        gzip.decompress(path.read_bytes()).decode("utf-8")
        for path in gzip_files
        if path.name.endswith(".js.gz")
    )
    server = (project / "components" / "lumia_web" / "web_server.c").read_text(encoding="utf-8")

    assert "http://" not in html.lower() and "https://" not in html.lower()
    for reference in re.findall(r'(?:src|href)="(/[^"]+)"', html):
        target = web / reference.lstrip("/")
        if target.suffix in {".html", ".css", ".js", ".json", ".svg"}:
            target = target.with_name(target.name + ".gz")
        assert target.is_file(), reference
    for endpoint in (
        "/api/v1/state",
        "/api/v1/scene",
        "/api/v1/global",
        "/api/v1/groups",
        "/api/v1/diagnostics/clear",
    ):
        assert endpoint in javascript
    assert 'return "image/webp"' in server
    assert "should_serve_gzip" in server
    for field in (
        "ledTxErrorCount",
        "ledGpioSwitchErrorCount",
        "ledInitErrorCount",
        "ledMaxScanGapUs",
    ):
        assert field in server
        assert field in javascript
    for content in ("Maurya123", "192.168.4.2/24", "OFFLINE GUIDE"):
        assert content in javascript
    assert "all-group-mode-buttons" in javascript
    assert "点滅速度" in javascript
    if args.variant == "ja":
        assert "v1.8.2-jp" in javascript
        assert "language-button" not in javascript
    else:
        assert "v1.8.2" in javascript
        assert "language-button" in javascript
        for chinese_ui in ("控制台", "使用说明", "频闪", "清零诊断", "正在连接"):
            assert chinese_ui in javascript
    source = (project / "web_ui" / "src" / "App.vue").read_text(encoding="utf-8")
    assert 'const { innerMode, hue, sat, value, innerParam }' in source
    assert 'v-for="mode in [1, 3]"' in source
    assert '<select v-model.number="group.innerMode"' not in source
    assert '<select v-model.number="state.groups[0].innerMode"' not in source

    assert len(palette["franchises"]) == 4
    assert len(palette["groups"]) == 31
    assert len(palette["characters"]) == 505
    forbidden = {"image", "sourceUrl", "imageSourceUrl"}
    franchise_ids = {item["id"] for item in palette["franchises"]}
    group_ids = {item["id"] for item in palette["groups"]}
    for collection in palette.values():
        for item in collection:
            assert not forbidden.intersection(item)
            if "hex" in item:
                assert re.fullmatch(r"#[0-9A-Fa-f]{6}", item["hex"])
    for group in palette["groups"]:
        assert group["franchiseId"] in franchise_ids
        assert group["nameZh"] and group["nameJa"]
        assert (web / "group-icons" / group["icon"]).is_file()
    for character in palette["characters"]:
        assert character["groupId"] in group_ids
        assert "id" not in character
        assert "franchiseId" not in character
        assert character["nameZh"] and character["nameJa"]
        assert (web / "avatars" / character["avatar"]).is_file()

    imas = sorted(
        (item for item in palette["groups"] if item["franchiseId"] == "imas"),
        key=lambda item: item["sortOrder"],
    )
    assert len(imas) == 8 and imas[-1]["nameZh"] == "其他"
    assert sum(path.stat().st_size for path in web.rglob("*") if path.is_file()) <= 1_850_000
    print("web asset tests passed")


if __name__ == "__main__":
    main()
