from __future__ import annotations

import argparse
import json
import shutil
from io import BytesIO
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]


def encode_webp(source: Path, size: int, quality: int) -> bytes:
    with Image.open(source) as image:
        image = image.convert("RGBA").resize((size, size), Image.Resampling.LANCZOS)
        output = BytesIO()
        image.save(output, "WEBP", quality=quality, method=6, exact=False)
        return output.getvalue()


def encode_logo_webp(source: Path) -> bytes:
    with Image.open(source) as image:
        image = image.convert("RGBA")
        alpha_box = image.getchannel("A").getbbox()
        if alpha_box:
            image = image.crop(alpha_box)
        image.thumbnail((120, 72), Image.Resampling.LANCZOS)
        canvas = Image.new("RGBA", (128, 80), (0, 0, 0, 0))
        canvas.alpha_composite(image, ((128 - image.width) // 2, (80 - image.height) // 2))
        output = BytesIO()
        canvas.save(output, "WEBP", quality=75, method=6, exact=True)
        return output.getvalue()


def reset_dir(path: Path) -> None:
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build the compact Maurya Web palette")
    parser.add_argument("--catalog", type=Path, required=True)
    parser.add_argument("--assets-root", type=Path, required=True)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    catalog = args.catalog.resolve()
    assets = args.assets_root.resolve()
    data = json.loads(catalog.read_text(encoding="utf-8"))
    visible_groups = [
        group for group in data["groups"]
        if group.get("groupType") not in {"attribute", "unit"}
    ]
    visible_group_ids = {group["id"] for group in visible_groups}
    characters = [item for item in data["characters"] if item["groupId"] in visible_group_ids]
    if len(visible_groups) != 31 or len(characters) != 505:
        raise RuntimeError(f"unexpected palette counts: {len(visible_groups)} / {len(characters)}")

    public = ROOT / "public"
    reports = ROOT / "reports"
    selected_dir = public / "avatars"
    group_icon_dir = public / "group-icons"
    candidate_root = reports / "avatar_candidates"
    reset_dir(selected_dir)
    reset_dir(group_icon_dir)
    reset_dir(candidate_root)
    reports.mkdir(exist_ok=True)

    variants = (("64q45", 64, 45), ("96q62", 96, 62))
    metrics = {"sourceBytes": 0, "variants": {}}
    compact_characters = []
    sample_indexes = set(range(0, len(characters), max(1, len(characters) // 24)))
    sample_indexes = set(sorted(sample_indexes)[:24])
    contact_images = {name: [] for name, _, _ in variants}

    for variant, size, quality in variants:
        (candidate_root / variant).mkdir(parents=True)
        metrics["variants"][variant] = {"size": size, "quality": quality, "bytes": 0, "maxBytes": 0}

    for index, character in enumerate(characters):
        source = assets / character["image"]
        metrics["sourceBytes"] += source.stat().st_size
        filename = f"{index:03d}.webp"
        for variant, size, quality in variants:
            encoded = encode_webp(source, size, quality)
            target = candidate_root / variant / filename
            target.write_bytes(encoded)
            item_metrics = metrics["variants"][variant]
            item_metrics["bytes"] += len(encoded)
            item_metrics["maxBytes"] = max(item_metrics["maxBytes"], len(encoded))
            if variant == "96q62":
                (selected_dir / filename).write_bytes(encoded)
            if index in sample_indexes:
                with Image.open(BytesIO(encoded)) as sample:
                    contact_images[variant].append((sample.convert("RGBA"), character["nameZh"], character["hex"]))
        compact_characters.append({
            "groupId": character["groupId"],
            "nameZh": character["nameZh"],
            "nameJa": character["nameJa"],
            "hex": character["hex"].upper(),
            "sortOrder": character["sortOrder"],
            "avatar": filename,
        })

    compact_groups = []
    group_icon_bytes = 0
    for index, group in enumerate(visible_groups):
        filename = f"{index:02d}.webp"
        logo_source = ROOT / "sources" / "imas-logos" / f"{group['id']}.png"
        uses_official_logo = logo_source.exists()
        encoded = encode_logo_webp(logo_source) if uses_official_logo else encode_webp(assets / group["image"], 64, 60)
        (group_icon_dir / filename).write_bytes(encoded)
        group_icon_bytes += len(encoded)
        compact_group = {
            key: group[key]
            for key in ("id", "franchiseId", "seriesLabelZh", "seriesLabelJa", "nameZh", "nameJa", "hex", "sortOrder")
        }
        compact_group["icon"] = filename
        compact_group["officialLogo"] = uses_official_logo
        compact_groups.append(compact_group)

    compact = {
        "franchises": [
            {
                key: item[key]
                for key in ("id", "label", "labelZh", "labelJa", "sortOrder")
                if key in item
            }
            for item in data["franchises"]
        ],
        "groups": compact_groups,
        "characters": compact_characters,
    }
    public.mkdir(exist_ok=True)
    (public / "palette.json").write_text(json.dumps(compact, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")

    for variant, entries in contact_images.items():
        tile = 104
        columns = 6
        rows = (len(entries) + columns - 1) // columns
        sheet = Image.new("RGB", (columns * tile, rows * 132), "#0b0d13")
        draw = ImageDraw.Draw(sheet)
        for index, (avatar, name, color) in enumerate(entries):
            x = (index % columns) * tile
            y = (index // columns) * 132
            avatar = avatar.resize((72, 72), Image.Resampling.NEAREST)
            sheet.paste(avatar, (x + 16, y + 8), avatar)
            draw.rectangle((x + 16, y + 84, x + 88, y + 91), fill=color)
            draw.text((x + 7, y + 98), name[:8], fill="#f0f1f7")
            draw.text((x + 20, y + 113), color, fill="#a9afc0")
        sheet.save(reports / f"comparison-{variant}.png", optimize=True)

    for item in metrics["variants"].values():
        item["averageBytes"] = round(item["bytes"] / len(characters), 2)
    (reports / "avatar-metrics.json").write_text(json.dumps(metrics, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({
        "groups": len(visible_groups),
        "groupIconBytes": group_icon_bytes,
        "characters": len(characters),
        **metrics,
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
