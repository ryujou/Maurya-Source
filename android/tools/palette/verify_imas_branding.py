from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image


REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPO_ROOT / "tools" / "palette" / "sources" / "imas_logos"
ASSET_ROOT = REPO_ROOT / "app" / "src" / "main" / "assets"
CATALOG_PATH = ASSET_ROOT / "palette" / "palette_catalog.json"
EXPECTED_IDS = {
    "imas_765as",
    "imas_cinderella",
    "imas_million",
    "imas_sidem",
    "imas_shiny",
    "imas_gakuen",
    "imas_ds_valiv",
    "imas_other",
}
EXPECTED_CHARACTER_ID_HEX_SHA256 = "009447199c21f5a94c10167ba6b8b008bf3b542f5b6bd8f9770b93c090dbe031"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    manifest = json.loads((SOURCE_ROOT / "manifest.json").read_text(encoding="utf-8"))
    records = {item["id"]: item for item in manifest["assets"]}
    assert set(records) == EXPECTED_IDS
    assert manifest["retrievedAt"] == "2026-07-19"

    for group_id, record in records.items():
        source = SOURCE_ROOT / record["sourceFile"]
        rendered = SOURCE_ROOT / record["renderedFile"]
        assert source.is_file() and rendered.is_file()
        assert sha256(source) == record["sourceSha256"]
        assert sha256(rendered) == record["renderedSha256"]
        assert record["sourcePage"].startswith("https://")
        assert record["licenseNote"]

    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    imas_groups = {
        item["id"]: item
        for item in catalog["groups"]
        if item["franchiseId"] == "imas" and item["groupType"] == "brand"
    }
    assert set(imas_groups) == EXPECTED_IDS
    for group in imas_groups.values():
        assert group["imageKind"] == "logo"
        image_path = ASSET_ROOT / group["image"]
        with Image.open(image_path) as image:
            assert image.size == (320, 160)
            assert image.mode == "RGBA"
            alpha = image.getchannel("A")
            assert alpha.getextrema() == (0, 255)
            assert alpha.getbbox() not in (None, (0, 0, 320, 160))

    characters = [item for item in catalog["characters"] if item["franchiseId"] != "vocaloid"]
    assert len(characters) == 475
    assert len({item["id"] for item in characters}) == 475
    character_fingerprint = "\n".join(
        f"{item['id']}={item['hex']}" for item in sorted(characters, key=lambda item: item["id"])
    ).encode("utf-8")
    assert hashlib.sha256(character_fingerprint).hexdigest() == EXPECTED_CHARACTER_ID_HEX_SHA256
    valiv = imas_groups["imas_ds_valiv"]
    other = imas_groups["imas_other"]
    assert valiv["nameZh"] == valiv["nameJa"] == "vα-liv"
    assert set(valiv["memberIds"]) == {
        "imas_char_210003",
        "imas_char_210004",
        "imas_char_210005",
    }
    assert set(other["memberIds"]) == {
        "imas_char_210001",
        "imas_char_210002",
        "imas_char_220001",
        "imas_char_230001",
    }
    print("IMAS branding assets verified: 8 logos, 475 unchanged character IDs")


if __name__ == "__main__":
    main()
