from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

from PIL import Image


REPO_ROOT = Path(__file__).resolve().parents[2]
PALETTE_ROOT = REPO_ROOT / "app" / "src" / "main" / "assets" / "palette"
SOURCE_ROOT = REPO_ROOT / "tools" / "palette" / "sources" / "vocaloid"
HEX_RE = re.compile(r"#[0-9A-F]{6}")


def main() -> None:
    catalog = json.loads((PALETTE_ROOT / "palette_catalog.json").read_text(encoding="utf-8"))
    manifest = json.loads((SOURCE_ROOT / "manifest.json").read_text(encoding="utf-8"))
    vocaloid = [item for item in catalog["characters"] if item["franchiseId"] == "vocaloid"]
    groups = [item for item in catalog["groups"] if item["franchiseId"] == "vocaloid"]

    assert (len(catalog["franchises"]), len(catalog["groups"]), len(catalog["characters"])) == (4, 55, 505)
    assert len({item["id"] for item in catalog["characters"]}) == 505
    assert {item["id"] for item in groups} == {"vocaloid_zh", "vocaloid_ja"}
    assert sum(item["groupId"] == "vocaloid_zh" for item in vocaloid) == 12
    assert sum(item["groupId"] == "vocaloid_ja" for item in vocaloid) == 18
    assert len(manifest["characters"]) == 30

    records = {item["id"]: item for item in manifest["characters"]}
    assert set(records) == {item["id"] for item in vocaloid}
    for character in vocaloid:
        assert character["nameZh"] and character["nameJa"]
        assert HEX_RE.fullmatch(character["hex"])
        record = records[character["id"]]
        assert record["faceReview"] == "approved-single-face"
        assert set(record["crop"]) == {"centerXRatio", "centerYRatio", "sideRatio"}
        source = SOURCE_ROOT / "originals" / record["sourceFile"]
        assert hashlib.sha256(source.read_bytes()).hexdigest() == record["sha256"]
        avatar = REPO_ROOT / "app" / "src" / "main" / "assets" / character["image"]
        with Image.open(avatar) as image:
            assert image.size == (96, 96)
            assert len(image.convert("RGB").getcolors(maxcolors=96 * 96) or []) > 64

    for size in (64, 96):
        assert (SOURCE_ROOT / "review" / f"faces-{size}.png").is_file()
    print("VOCALOID palette verified: 4/55/505, 12 Chinese + 18 Japanese, 30 reviewed faces")


if __name__ == "__main__":
    main()
