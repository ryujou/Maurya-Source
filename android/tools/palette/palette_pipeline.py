from __future__ import annotations

import hashlib
import json
import math
import re
import shutil
import subprocess
import warnings
from collections import defaultdict
from dataclasses import dataclass
from functools import lru_cache
from io import BytesIO
from pathlib import Path
from typing import Any
from urllib.parse import quote, urljoin

import requests
from bs4 import BeautifulSoup
from PIL import Image, ImageDraw, ImageFont

warnings.filterwarnings("ignore")


REPO_ROOT = Path(__file__).resolve().parents[2]
TOOLS_ROOT = REPO_ROOT / "tools" / "palette"
MODELS_ROOT = TOOLS_ROOT / "models"
GENERATED_ROOT = TOOLS_ROOT / "generated"
IMAGE_CACHE_ROOT = TOOLS_ROOT / "cache" / "images"
AVATAR_OVERRIDES_PATH = TOOLS_ROOT / "avatar_overrides.json"
ASSETS_ROOT = REPO_ROOT / "app" / "src" / "main" / "assets"
PALETTE_ROOT = ASSETS_ROOT / "palette"
PALETTE_GROUPS_ROOT = PALETTE_ROOT / "groups"
PALETTE_CHARACTERS_ROOT = PALETTE_ROOT / "characters"
BANGDREAM_LOCALES_PATH = MODELS_ROOT / "bangdream_locales.json"
LOVELIVE_LOCALES_PATH = MODELS_ROOT / "lovelive_locales.json"
VOCALOID_CATALOG_PATH = MODELS_ROOT / "vocaloid_catalog.json"

LLWIKI_URL = "https://llwiki.org/zh/LoveLive%21%E7%B3%BB%E5%88%97%E6%87%89%E6%8F%B4%E8%89%B2%E5%88%97%E8%A1%A8"
IMAS_COLOR_URL = "https://imas-db.jp/misc/color.html"
IMAS_IDOLLIST_URL = "https://idollist.idolmaster-official.jp/search"
IMAS_LOGO_MANIFEST_PATH = TOOLS_ROOT / "sources" / "imas_logos" / "manifest.json"

HTTP_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/136.0.0.0 Safari/537.36"
    ),
}

HEX_RE = re.compile(r"#([0-9a-fA-F]{6})")
IMAS_CV_SUFFIX_RE = re.compile(r"\(.*?\)$")


BANGDREAM_GROUP_CONFIG = [
    ("Poppin'Party", "#FF69B4", "band_icon/Popipa_icon.png", "PP"),
    ("Afterglow", "#9B2423", "band_icon/Afterglow_icon.png", "AG"),
    ("Pastel*Palettes", "#B9CEAC", "band_icon/Pastel_Palettes_icon.png", "PPa"),
    ("Roselia", "#00008B", "band_icon/Roselia_icon.png", "RO"),
    ("Hello, Happy World!", "#FFD700", "band_icon/HHW_icon.png", "HHW"),
    ("Morfonica", "#007CB0", "band_icon/Morfonica_icon.png", "MF"),
    ("RAISE A SUILEN", "#61993B", "band_icon/RAS_icon_HD.png", "RAS"),
    ("MyGO!!!!!", "#4682B4", "band_icon/MyGO_icon.png", "MG"),
    ("Ave Mujica", "#8B0000", "band_icon/Icon_Ave_Mujica_temp.png", "AM"),
    ("\u68a6\u9650\u5927MewType", "#FF1493", "band_icon/Mugendai_muw_type_icon.png", "MT"),
    ("\u4e00\u5bb6Dumb Rock!", "#F4AF48", "band_icon/Icon_ikka.png", "DR"),
    ("millsage", "#9C25ED", "band_icon/Icon_millsage.png", "MS"),
]

LOVELIVE_DEFAULT_GROUP_BY_SERIES = {
    "LoveLive!": "\u03bc's",
    "LoveLive!\u8679\u54b2\u5b66\u56ed\u5b66\u56ed\u5076\u50cf\u540c\u597d\u4f1a": "\u8679\u54b2\u5b66\u56ed\u5b66\u56ed\u5076\u50cf\u540c\u597d\u4f1a",
    "LoveLive! Superstar!!": "Liella!",
    "SCHOOL IDOL MUSICAL": "SCHOOL IDOL MUSICAL",
    "\u83b2\u4e4b\u7a7a\u5973\u5b66\u9662\u5b66\u56ed\u5076\u50cf\u4ff1\u4e50\u90e8": "\u83b2\u4e4b\u7a7a\u5973\u5b66\u9662\u5b66\u56ed\u5076\u50cf\u4ff1\u4e50\u90e8",
    "IKIZULIVE! LOVELIVE! BLUEBIRD": "IKIZULIVE! LOVELIVE! BLUEBIRD",
}

LOVELIVE_SERIES_LABELS = {
    "LoveLive!": "LoveLive!",
    "LoveLive! Sunshine!!": "Sunshine!!",
    "LoveLive!\u8679\u54b2\u5b66\u56ed\u5b66\u56ed\u5076\u50cf\u540c\u597d\u4f1a": "\u8679\u54b2",
    "LoveLive! Superstar!!": "Superstar!!",
    "SCHOOL IDOL MUSICAL": "SCHOOL IDOL MUSICAL",
    "\u83b2\u4e4b\u7a7a\u5973\u5b66\u9662\u5b66\u56ed\u5076\u50cf\u4ff1\u4e50\u90e8": "\u83b2\u4e4b\u7a7a",
    "IKIZULIVE! LOVELIVE! BLUEBIRD": "IKIZULIVE",
}

LOVELIVE_GROUP_ICON_TEXT = {
    "\u03bc's": "MU",
    "Aqours": "AQ",
    "Saint Snow": "SS",
    "\u8679\u54b2\u5b66\u56ed\u5b66\u56ed\u5076\u50cf\u540c\u597d\u4f1a": "NIJI",
    "Liella!": "LI",
    "Sunny Passion": "SP",
    "SCHOOL IDOL MUSICAL": "SIM",
    "\u83b2\u4e4b\u7a7a\u5973\u5b66\u9662\u5b66\u56ed\u5076\u50cf\u4ff1\u4e50\u90e8": "HS",
    "IKIZULIVE! LOVELIVE! BLUEBIRD": "IKI",
}

IMAS_VISIBLE_GROUPS = [
    {
        "id": "imas_765as",
        "name": "765PRO\u5168\u660e\u661f",
        "name_ja": "765PRO ALLSTARS",
        "source_name": "765PRO ALLSTARS",
        "sort_order": 1,
        "brand_ids": {1},
        "fallback_text": "765",
    },
    {
        "id": "imas_cinderella",
        "name": "\u7070\u59d1\u5a18\u5973\u5b69",
        "name_ja": "\u30b7\u30f3\u30c7\u30ec\u30e9\u30ac\u30fc\u30eb\u30ba",
        "source_name": "\u30b7\u30f3\u30c7\u30ec\u30e9\u30ac\u30fc\u30eb\u30ba",
        "sort_order": 2,
        "brand_ids": {2},
        "fallback_text": "CG",
    },
    {
        "id": "imas_million",
        "name": "\u767e\u4e07\u73b0\u573a\uff01",
        "name_ja": "\u30df\u30ea\u30aa\u30f3\u30e9\u30a4\u30d6\uff01",
        "source_name": "\u30df\u30ea\u30aa\u30f3\u30e9\u30a4\u30d6\uff01",
        "sort_order": 3,
        "brand_ids": {3},
        "fallback_text": "ML",
    },
    {
        "id": "imas_sidem",
        "name": "SideM",
        "name_ja": "SideM",
        "source_name": "SideM",
        "sort_order": 4,
        "brand_ids": {4, 25},
        "fallback_text": "SM",
    },
    {
        "id": "imas_shiny",
        "name": "\u95ea\u8000\u8272\u5f69",
        "name_ja": "\u30b7\u30e3\u30a4\u30cb\u30fc\u30ab\u30e9\u30fc\u30ba",
        "source_name": "\u30b7\u30e3\u30a4\u30cb\u30fc\u30ab\u30e9\u30fc\u30ba",
        "sort_order": 5,
        "brand_ids": {5},
        "fallback_text": "SC",
    },
    {
        "id": "imas_gakuen",
        "name": "\u5b66\u56ed\u5076\u50cf\u5927\u5e08",
        "name_ja": "\u5b66\u5712\u30a2\u30a4\u30c9\u30eb\u30de\u30b9\u30bf\u30fc",
        "source_name": "\u5b66\u5712\u30a2\u30a4\u30c9\u30eb\u30de\u30b9\u30bf\u30fc",
        "sort_order": 6,
        "brand_ids": {6},
        "fallback_text": "GA",
    },
    {
        "id": "imas_ds_valiv",
        "name": "v\u03b1-liv",
        "name_ja": "v\u03b1-liv",
        "source_name": "\u30f4\u30a4\u30a2\u30e9\u30a4\u30f4",
        "sort_order": 7,
        "brand_ids": {21},
        "fallback_text": "VL",
    },
    {
        "id": "imas_other",
        "name": "\u5176\u4ed6",
        "name_ja": "\u305d\u306e\u4ed6",
        "source_name": "\u305d\u306e\u4ed6",
        "sort_order": 8,
        "brand_ids": {24},
        "fallback_text": "OTH",
    },
]

IMAS_SECTION_BRANDS = {
    "765PRO ALLSTARS & 961\u30d7\u30ed\u30a2\u30a4\u30c9\u30eb": {1, 22, 23},
    "\u30b7\u30f3\u30c7\u30ec\u30e9\u30ac\u30fc\u30eb\u30ba": {2},
    "\u30df\u30ea\u30aa\u30f3\u30e9\u30a4\u30d6\uff01": {3},
    "SideM": {4, 25},
    "\u30b7\u30e3\u30a4\u30cb\u30fc\u30ab\u30e9\u30fc\u30ba": {5},
    "\u5b66\u5712\u30a2\u30a4\u30c9\u30eb\u30de\u30b9\u30bf\u30fc": {6},
    "\u30c7\u30a3\u30a2\u30ea\u30fc\u30b9\u30bf\u30fc\u30ba": {21},
    "\u30f4\u30a4\u30a2\u30e9\u30a4\u30f4": {21},
}

IMAS_ATTRIBUTE_ROWS = {
    "\u30ad\u30e5\u30fc\u30c8",
    "\u30af\u30fc\u30eb",
    "\u30d1\u30c3\u30b7\u30e7\u30f3",
}

IMAS_SERIES_LABEL_ZH = "\u4f01\u5212"
IMAS_SERIES_LABEL_JA = "\u4f01\u753b"

@dataclass
class PaletteEntry:
    id: str
    franchise_id: str
    series_label: str
    name: str
    hex: str
    image: str
    source_url: str
    image_source_url: str
    sort_order: int


def generated_file(name: str) -> Path:
    return GENERATED_ROOT / name


def ensure_dirs() -> None:
    GENERATED_ROOT.mkdir(parents=True, exist_ok=True)
    IMAGE_CACHE_ROOT.mkdir(parents=True, exist_ok=True)
    PALETTE_GROUPS_ROOT.mkdir(parents=True, exist_ok=True)
    PALETTE_CHARACTERS_ROOT.mkdir(parents=True, exist_ok=True)


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


@lru_cache(maxsize=None)
def load_locale_model(path: str) -> dict[str, Any]:
    return read_json(MODELS_ROOT / path)


@lru_cache(maxsize=1)
def load_avatar_overrides() -> dict[str, dict[str, float]]:
    overrides = read_json(AVATAR_OVERRIDES_PATH) if AVATAR_OVERRIDES_PATH.exists() else {}
    if VOCALOID_CATALOG_PATH.exists():
        for character in read_json(VOCALOID_CATALOG_PATH).get("characters", []):
            crop = character.get("crop")
            if crop:
                overrides[character["id"]] = crop
    return overrides


def stable_hash(text: str) -> str:
    return hashlib.sha1(text.encode("utf-8")).hexdigest()[:12]


def normalize_hex(raw: str | None) -> str | None:
    if not raw:
        return None
    match = HEX_RE.search(raw)
    if not match:
        return None
    return f"#{match.group(1).upper()}"


def extract_hex(raw: str | None) -> str | None:
    return normalize_hex(raw)


def hex_to_rgb(value: str) -> tuple[int, int, int]:
    value = normalize_hex(value) or "#000000"
    return tuple(int(value[index : index + 2], 16) for index in (1, 3, 5))


def average_hex(values: list[str]) -> str:
    rgbs = [hex_to_rgb(value) for value in values if normalize_hex(value)]
    if not rgbs:
        return "#808080"
    red = round(sum(rgb[0] for rgb in rgbs) / len(rgbs))
    green = round(sum(rgb[1] for rgb in rgbs) / len(rgbs))
    blue = round(sum(rgb[2] for rgb in rgbs) / len(rgbs))
    return f"#{red:02X}{green:02X}{blue:02X}"


def clean_text(raw: str) -> str:
    return re.sub(r"\s+", " ", raw or "").strip()


def fetch_text(url: str) -> str:
    response = requests.get(url, headers=HTTP_HEADERS, timeout=30)
    response.raise_for_status()
    return response.content.decode("utf-8", errors="replace")


def fetch_curl_text(url: str) -> str:
    return subprocess.check_output(
        ["curl.exe", "-L", "-s", url],
        text=True,
        encoding="utf-8",
        errors="replace",
    )


def fetch_bytes(url: str, referer_url: str | None = None) -> bytes:
    cache_key = stable_hash(f"{url}|{referer_url or ''}")
    suffix = Path(url.split("?", 1)[0]).suffix.lower() or ".bin"
    cache_path = IMAGE_CACHE_ROOT / f"{cache_key}{suffix}"
    if cache_path.exists():
        return cache_path.read_bytes()

    last_error: Exception | None = None
    for _ in range(3):
        try:
            if "llwiki.org" in url:
                command = ["curl.exe", "-L", "-s"]
                if referer_url:
                    command.extend(["-e", referer_url])
                command.append(url)
                payload = subprocess.check_output(command)
                cache_path.parent.mkdir(parents=True, exist_ok=True)
                cache_path.write_bytes(payload)
                return payload
            response = requests.get(url, headers=HTTP_HEADERS, timeout=30)
            response.raise_for_status()
            cache_path.parent.mkdir(parents=True, exist_ok=True)
            cache_path.write_bytes(response.content)
            return response.content
        except Exception as exc:
            last_error = exc
    if last_error is not None:
        raise last_error
    raise RuntimeError(f"Failed to fetch bytes from {url}")


def normalize_image_src(page_url: str, src: str) -> str:
    if src.startswith("//"):
        return f"https:{src}"
    return urljoin(page_url, src)


def sanitize_slug(raw: str) -> str:
    lowered = re.sub(r"[^a-zA-Z0-9]+", "-", raw).strip("-").lower()
    if lowered:
        return lowered
    return stable_hash(raw)


def crop_square_image(source: Image.Image, size: int = 96) -> Image.Image:
    image = source.convert("RGBA")
    width, height = image.size
    side = min(width, height)
    left = (width - side) // 2
    top = (height - side) // 2
    return image.crop((left, top, left + side, top + side)).resize(
        (size, size),
        Image.Resampling.LANCZOS,
    )


def clamp_int(value: int, lower: int, upper: int) -> int:
    return max(lower, min(upper, value))


def focused_square_crop(
    source: Image.Image,
    *,
    center_x: float,
    center_y: float,
    side: float,
    size: int = 96,
) -> Image.Image:
    image = source.convert("RGBA")
    width, height = image.size
    square_side = clamp_int(int(round(side)), 1, min(width, height))
    left = clamp_int(int(round(center_x - square_side / 2)), 0, width - square_side)
    top = clamp_int(int(round(center_y - square_side / 2)), 0, height - square_side)
    return image.crop((left, top, left + square_side, top + square_side)).resize(
        (size, size),
        Image.Resampling.LANCZOS,
    )


def crop_avatar_image(
    source: Image.Image,
    *,
    character_id: str | None = None,
    franchise_id: str | None = None,
    size: int = 96,
) -> Image.Image:
    image = source.convert("RGBA")
    width, height = image.size
    alpha_bbox = image.getchannel("A").getbbox()

    override = load_avatar_overrides().get(character_id or "")
    if override:
        side = min(width, height) * float(override["sideRatio"])
        return focused_square_crop(
            image,
            center_x=width * float(override["centerXRatio"]),
            center_y=height * float(override["centerYRatio"]),
            side=side,
            size=size,
        )

    # LoveLive! source art is usually a transparent full-body standing pose.
    # Center-cropping grabs too much torso, so bias the square toward the head.
    if franchise_id == "lovelive" and alpha_bbox and alpha_bbox != (0, 0, width, height):
        left, top, right, bottom = alpha_bbox
        bbox_width = right - left
        bbox_height = bottom - top
        return focused_square_crop(
            image,
            center_x=left + bbox_width / 2,
            center_y=top + bbox_height * 0.18,
            side=max(bbox_width * 0.95, bbox_height * 0.33),
            size=size,
        )

    # IMAS official art is usually landscape card artwork.
    # A smaller upper-center crop produces a real avatar instead of a full card.
    if franchise_id == "imas" and width >= height * 1.15:
        return focused_square_crop(
            image,
            center_x=width * 0.50,
            center_y=height * 0.30,
            side=min(height, max(height * 0.72, width * 0.42)),
            size=size,
        )

    # Fallback for other tall transparent portraits.
    if alpha_bbox and alpha_bbox != (0, 0, width, height):
        left, top, right, bottom = alpha_bbox
        bbox_width = right - left
        bbox_height = bottom - top
        if bbox_height > bbox_width * 1.10:
            return focused_square_crop(
                image,
                center_x=left + bbox_width / 2,
                center_y=top + bbox_height * 0.30,
                side=max(bbox_width * 1.30, bbox_height * 0.55),
                size=size,
            )

    return crop_square_image(image, size=size)


def contain_on_canvas(
    source: Image.Image,
    width: int = 96,
    height: int = 96,
    padding: int = 0,
) -> Image.Image:
    image = source.convert("RGBA")
    image.thumbnail((width - padding * 2, height - padding * 2), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    left = (width - image.width) // 2
    top = (height - image.height) // 2
    canvas.paste(image, (left, top), image)
    return canvas


def save_processed_image(
    dest_path: Path,
    *,
    source_url: str | None = None,
    source_asset: str | None = None,
    referer_url: str | None = None,
    mode: str,
    character_id: str | None = None,
    franchise_id: str | None = None,
) -> bool:
    if source_asset:
        normalized_asset = source_asset.replace("\\", "/")
        if normalized_asset.startswith("tools:"):
            source_path = TOOLS_ROOT / normalized_asset.removeprefix("tools:")
        else:
            source_path = ASSETS_ROOT / normalized_asset.removeprefix("assets/")
        if not source_path.exists():
            return False
        image = Image.open(source_path)
    elif source_url:
        try:
            image = Image.open(BytesIO(fetch_bytes(source_url, referer_url=referer_url)))
        except Exception:
            return False
    else:
        return False

    ensure_dirs()
    dest_path.parent.mkdir(parents=True, exist_ok=True)
    processed = (
        crop_avatar_image(
            image,
            character_id=character_id,
            franchise_id=franchise_id,
        )
        if mode == "avatar"
        else contain_on_canvas(image, width=320, height=160, padding=12)
        if mode == "group_logo"
        else contain_on_canvas(image)
    )
    processed.save(dest_path, format="PNG")
    return True


def require_localized_name(mapping: dict[str, str], value: str, *, label: str) -> str:
    normalized = clean_text(value)
    localized = clean_text(mapping.get(normalized, ""))
    if not normalized or not localized:
        raise RuntimeError(f"Missing {label} for {value}")
    return localized


def make_circle_icon(dest_path: Path, bg_hex: str, text: str) -> None:
    ensure_dirs()
    dest_path.parent.mkdir(parents=True, exist_ok=True)
    image = Image.new("RGBA", (96, 96), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.ellipse((4, 4, 92, 92), fill=hex_to_rgb(bg_hex) + (255,))

    label = (text or "?").strip()[:4]
    font = ImageFont.load_default(size=20)
    bbox = draw.textbbox((0, 0), label, font=font)
    width = bbox[2] - bbox[0]
    height = bbox[3] - bbox[1]
    draw.text(
        ((96 - width) / 2, (96 - height) / 2 - 1),
        label,
        font=font,
        fill=(255, 255, 255, 255),
    )
    image.save(dest_path, format="PNG")


@lru_cache(maxsize=None)
def first_llwiki_content_image(page_url: str) -> str | None:
    try:
        html = fetch_curl_text(page_url)
    except Exception:
        return None
    soup = BeautifulSoup(html, "html.parser")
    for image in soup.select(".mw-parser-output img"):
        src = image.get("src", "").strip()
        if not src:
            continue
        normalized = normalize_image_src(page_url, src)
        if any(
            token in normalized
            for token in (
                "/resources/assets/",
                "logo.png",
                "cc-by",
                "poweredby_mediawiki",
                "\u5167\u5bb9\u7f3a\u5931",
                "%E5%85%A7%E5%AE%B9%E7%BC%BA%E5%A4%B1",
                "Symbol-",
                "Signature-",
            )
        ):
            continue
        width = int(image.get("width", "0") or 0)
        height = int(image.get("height", "0") or 0)
        if max(width, height) < 80:
            continue
        return normalized
    return None


@lru_cache(maxsize=None)
def first_imas_detail_image(character_id: int) -> str | None:
    detail_url = f"https://idollist.idolmaster-official.jp/detail/{character_id}"
    try:
        html = fetch_text(detail_url)
    except Exception:
        return None
    match = re.search(
        r"https://idollist\.idolmaster-official\.jp/images/character_main/[^\"']+",
        html,
    )
    return match.group(0) if match else None


def resolve_imas_character_image(official: dict[str, Any]) -> str:
    label = clean_text(str(official.get("identification_label", "")))
    if label:
        return f"https://idollist.idolmaster-official.jp/images/character_main/{label}_01.jpg"
    return first_imas_detail_image(int(official["character_id"])) or ""


def crawl_bangdream() -> dict[str, Any]:
    data = read_json(ASSETS_ROOT / "bangdream_avatars.json")
    locales = load_locale_model("bangdream_locales.json")
    character_name_ja = locales["characterNameJaByZh"]
    group_configs = {name: (color, icon, fallback, order) for order, (name, color, icon, fallback) in enumerate(BANGDREAM_GROUP_CONFIG, start=1)}

    franchise = {"id": "bangdream", "label": "BangDream", "sortOrder": 1}
    groups: list[dict[str, Any]] = []
    characters: list[dict[str, Any]] = []
    member_ids_by_group: dict[str, list[str]] = defaultdict(list)

    for band_name, (hex_value, icon_path, fallback_text, order) in group_configs.items():
        group_id = f"bangdream_{sanitize_slug(band_name)}"
        groups.append(
            {
                "id": group_id,
                "franchiseId": "bangdream",
                "seriesLabelZh": "BangDream",
                "seriesLabelJa": locales.get("seriesLabelJa", "BanG Dream!"),
                "nameZh": band_name,
                "nameJa": band_name,
                "sourceName": band_name,
                "hex": normalize_hex(hex_value),
                "sourceUrl": "",
                "imageSourceUrl": "",
                "sourceImageAsset": icon_path,
                "groupType": "band",
                "sortOrder": order,
                "memberIds": [],
                "fallbackText": fallback_text,
            }
        )

    for index, item in enumerate(data.get("items", []), start=1):
        band_name = clean_text(item.get("band", ""))
        if band_name not in group_configs:
            continue
        group_id = f"bangdream_{sanitize_slug(band_name)}"
        char_id = f"bangdream_char_{index:03d}"
        name_zh = clean_text(item.get("name", ""))
        member_ids_by_group[group_id].append(char_id)
        characters.append(
            {
                "id": char_id,
                "franchiseId": "bangdream",
                "groupId": group_id,
                "nameZh": name_zh,
                "nameJa": require_localized_name(
                    character_name_ja,
                    name_zh,
                    label="BangDream Japanese character name",
                ),
                "hex": normalize_hex(item.get("color")) or "#FF66AA",
                "sourceUrl": clean_text(item.get("source_url", "")),
                "imageSourceUrl": clean_text(item.get("source_url", "")),
                "sourceImageAsset": clean_text(item.get("image", "")),
                "sortOrder": index,
            }
        )

    for group in groups:
        group["memberIds"] = member_ids_by_group.get(group["id"], [])

    payload = {
        "franchises": [franchise],
        "groups": groups,
        "characters": characters,
    }
    write_json(generated_file("bangdream.json"), payload)
    return payload


def crawl_lovelive() -> dict[str, Any]:
    locales = load_locale_model("lovelive_locales.json")
    character_name_ja = locales["characterNameJaByZh"]
    group_name_ja = locales["groupNameJaByZh"]
    series_label_ja = locales["seriesLabelJaByZh"]
    excluded_characters = set(locales.get("excludedCharacters", []))

    html = fetch_curl_text(LLWIKI_URL)
    soup = BeautifulSoup(html, "html.parser")
    franchise = {"id": "lovelive", "label": "LoveLive!", "sortOrder": 2}
    groups_meta: list[tuple[str, str, int]] = []
    group_members: dict[str, list[dict[str, Any]]] = defaultdict(list)
    group_color_overrides: dict[str, str] = {}

    for table in soup.select("table.wikitable"):
        series_heading = table.find_previous("h2")
        if series_heading is None:
            continue
        raw_series = clean_text(series_heading.get_text(" ", strip=True))
        if raw_series in {"目录", "参见", "参考资料", "导航菜单"}:
            continue

        subgroup_heading = table.find_previous("h3")
        raw_group = None
        if subgroup_heading is not None:
            previous_h2 = subgroup_heading.find_previous("h2")
            if previous_h2 is not None and previous_h2 == series_heading:
                raw_group = clean_text(subgroup_heading.get_text(" ", strip=True))

        series_label = LOVELIVE_SERIES_LABELS.get(raw_series, raw_series)
        group_name = raw_group or LOVELIVE_DEFAULT_GROUP_BY_SERIES.get(raw_series, series_label)
        if not any(meta[0] == series_label and meta[1] == group_name for meta in groups_meta):
            groups_meta.append((series_label, group_name, len(groups_meta) + 1))

        for row in table.select("tr")[1:]:
            cells = row.select("td")
            if len(cells) < 4:
                continue
            anchor = cells[0].select_one("a[href]")
            name_text = clean_text(cells[0].get_text(" ", strip=True))
            hex_value = extract_hex(cells[3].get_text(" ", strip=True))
            if not anchor or not name_text or not hex_value:
                continue
            if name_text == group_name:
                group_color_overrides[group_name] = hex_value
                continue
            if name_text in excluded_characters:
                continue
            page_url = urljoin(LLWIKI_URL, anchor.get("href", ""))
            group_members[group_name].append(
                {
                    "nameZh": name_text,
                    "nameJa": require_localized_name(
                        character_name_ja,
                        name_text,
                        label="LoveLive Japanese character name",
                    ),
                    "hex": hex_value,
                    "sourceUrl": page_url,
                    "imageSourceUrl": first_llwiki_content_image(page_url) or "",
                }
            )

    groups: list[dict[str, Any]] = []
    characters: list[dict[str, Any]] = []
    for series_label, group_name, sort_order in groups_meta:
        members = group_members.get(group_name, [])
        group_id = f"lovelive_group_{sanitize_slug(group_name)}"
        if group_name in group_color_overrides:
            group_hex = group_color_overrides[group_name]
        elif members:
            group_hex = average_hex([member["hex"] for member in members])
        else:
            group_hex = "#999999"
        group_page_url = f"https://llwiki.org/zh/{quote(group_name, safe='')}"
        group_image_url = first_llwiki_content_image(group_page_url) or ""
        groups.append(
            {
                "id": group_id,
                "franchiseId": "lovelive",
                "seriesLabelZh": series_label,
                "seriesLabelJa": require_localized_name(
                    series_label_ja,
                    series_label,
                    label="LoveLive Japanese series label",
                ),
                "nameZh": group_name,
                "nameJa": require_localized_name(
                    group_name_ja,
                    group_name,
                    label="LoveLive Japanese group name",
                ),
                "sourceName": group_name,
                "hex": group_hex,
                "sourceUrl": group_page_url if group_image_url else LLWIKI_URL,
                "imageSourceUrl": group_image_url,
                "sourceImageAsset": "",
                "groupType": "group",
                "sortOrder": sort_order,
                "memberIds": [],
                "fallbackText": LOVELIVE_GROUP_ICON_TEXT.get(group_name, group_name[:3].upper()),
            }
        )
        for member_order, member in enumerate(members, start=1):
            char_id = f"lovelive_char_{stable_hash(group_name + ':' + member['nameZh'])}"
            characters.append(
                {
                    "id": char_id,
                    "franchiseId": "lovelive",
                    "groupId": group_id,
                    "nameZh": member["nameZh"],
                    "nameJa": member["nameJa"],
                    "hex": member["hex"],
                    "sourceUrl": member["sourceUrl"],
                    "imageSourceUrl": member["imageSourceUrl"],
                    "sourceImageAsset": "",
                    "sortOrder": member_order,
                }
            )
            groups[-1]["memberIds"].append(char_id)

    payload = {
        "franchises": [franchise],
        "groups": groups,
        "characters": characters,
    }
    write_json(generated_file("lovelive.json"), payload)
    return payload


def normalize_imas_name(raw: str) -> str:
    cleaned = IMAS_CV_SUFFIX_RE.sub("", raw).replace(" ", "")
    return clean_text(cleaned)


def split_imas_names(raw: str) -> list[str]:
    normalized = normalize_imas_name(raw)
    if normalized == "双海亜美/真美":
        return ["双海亜美", "双海真美"]
    return [normalized]


@lru_cache(maxsize=1)
def load_imas_official_index() -> list[dict[str, Any]]:
    html = fetch_text(IMAS_IDOLLIST_URL)
    match = re.search(r"window\.appCharacterList\s*=\s*(\[.*?\]);", html, re.S)
    if not match:
        raise RuntimeError("Failed to find IMAS official character index")
    items = json.loads(match.group(1))
    for item in items:
        item["matchName"] = clean_text(item["name"]).replace(" ", "")
    return items


def match_imas_official(
    source_name: str,
    allowed_brand_ids: set[int],
    official_items: list[dict[str, Any]],
) -> dict[str, Any] | None:
    match_name = clean_text(source_name).replace(" ", "")
    candidates = [
        item
        for item in official_items
        if int(item["brand_id"]) in allowed_brand_ids
    ]
    direct = [item for item in candidates if item["matchName"] == match_name]
    if len(direct) == 1:
        return direct[0]
    prefix = [
        item
        for item in candidates
        if item["matchName"].startswith(match_name) or match_name.startswith(item["matchName"])
    ]
    if len(prefix) == 1:
        return prefix[0]
    return None


def build_imas_visible_groups(brand_colors: dict[str, str]) -> dict[str, dict[str, Any]]:
    logo_assets = {
        item["id"]: item
        for item in read_json(IMAS_LOGO_MANIFEST_PATH)["assets"]
    }
    groups: dict[str, dict[str, Any]] = {}
    for config in IMAS_VISIBLE_GROUPS:
        color = brand_colors.get(config["source_name"])
        logo = logo_assets[config["id"]]
        groups[config["id"]] = {
            "id": config["id"],
            "franchiseId": "imas",
            "seriesLabelZh": IMAS_SERIES_LABEL_ZH,
            "seriesLabelJa": IMAS_SERIES_LABEL_JA,
            "nameZh": config["name"],
            "nameJa": config["name_ja"],
            "sourceName": config["source_name"],
            "hex": normalize_hex(color) or "#FF74B8",
            "sourceUrl": logo["sourcePage"],
            "imageSourceUrl": logo["downloadUrl"],
            "sourceImageAsset": f"tools:sources/imas_logos/{logo['renderedFile']}",
            "imageKind": "logo",
            "groupType": "brand",
            "sortOrder": config["sort_order"],
            "memberIds": [],
            "fallbackText": config["fallback_text"],
        }
    return groups

def crawl_imas() -> dict[str, Any]:
    html = fetch_text(IMAS_COLOR_URL)
    soup = BeautifulSoup(html, "html.parser")
    official_items = load_imas_official_index()

    franchise = {"id": "imas", "label": "THE IDOLM@STER", "sortOrder": 3}
    section_items = [
        (clean_text(section.select_one("h2").get_text(" ", strip=True)), section)
        for section in soup.select("section.tab-pane .section")
        if section.select_one("h2")
    ]
    sections = dict(section_items)
    brand_section_name = section_items[0][0]
    other_section_name = section_items[-1][0]

    brand_colors: dict[str, str] = {}
    overall_brand_hex = "#FF74B8"
    for row in sections[brand_section_name].select("tr")[1:]:
        cells = row.select("td")
        if len(cells) < 2:
            continue
        name = clean_text(cells[0].get_text(" ", strip=True))
        hex_value = extract_hex(cells[1].get_text(" ", strip=True))
        if name and hex_value:
            brand_colors[name] = hex_value
            if overall_brand_hex == "#FF74B8":
                overall_brand_hex = hex_value

    visible_groups = build_imas_visible_groups(brand_colors)
    extra_groups: dict[str, dict[str, Any]] = {}
    characters: list[dict[str, Any]] = []

    def group_id_for_character(brand_id: int, character_id: int) -> str:
        if character_id in {210001, 210002}:
            return "imas_other"
        for config in IMAS_VISIBLE_GROUPS:
            if brand_id in config["brand_ids"]:
                return config["id"]
        return "imas_other"

    def ensure_extra_group(section_name: str, name: str, hex_value: str, group_type: str) -> str:
        group_id = f"imas_extra_{sanitize_slug(section_name)}_{sanitize_slug(name)}"
        if group_id not in extra_groups:
            extra_groups[group_id] = {
                "id": group_id,
                "franchiseId": "imas",
                "seriesLabelZh": section_name,
                "seriesLabelJa": section_name,
                "nameZh": name,
                "nameJa": name,
                "sourceName": name,
                "hex": hex_value,
                "sourceUrl": IMAS_COLOR_URL,
                "imageSourceUrl": "",
                "sourceImageAsset": "",
                "groupType": group_type,
                "sortOrder": 1000 + len(extra_groups),
                "memberIds": [],
                "fallbackText": sanitize_slug(name).upper()[:4] or "IM",
            }
        return group_id

    for index, (section_name, section) in enumerate(section_items):
        if index == 0 or section_name == other_section_name:
            continue
        allowed_brands = IMAS_SECTION_BRANDS.get(section_name, set())
        is_cinderella = allowed_brands == {2}
        is_sidem_or_shiny = allowed_brands in ({4, 25}, {5})
        tables = section.select("table")
        for table_index, table in enumerate(tables):
            for row in table.select("tr")[1:]:
                cells = row.select("td")
                if len(cells) < 2:
                    continue
                row_name = clean_text(cells[0].get_text(" ", strip=True))
                row_hex = extract_hex(row.get_text(" ", strip=True))
                if not row_name or not row_hex or row_name.startswith("?"):
                    continue

                is_extra_group_row = False
                group_type = "unit"
                if is_cinderella and table_index == 0:
                    is_extra_group_row = True
                    group_type = "attribute"
                elif is_cinderella and table_index >= 2:
                    is_extra_group_row = True
                    group_type = "unit"
                elif is_sidem_or_shiny and "(" not in row_name:
                    is_extra_group_row = True
                    group_type = "unit"

                if is_extra_group_row:
                    ensure_extra_group(section_name, row_name, row_hex, group_type)
                    continue

                for member_name in split_imas_names(row_name):
                    official = match_imas_official(member_name, allowed_brands, official_items)
                    if not official:
                        continue
                    brand_id = int(official["brand_id"])
                    char_id = f"imas_char_{official['character_id']}"
                    group_id = group_id_for_character(brand_id, int(official["character_id"]))
                    if char_id in visible_groups[group_id]["memberIds"]:
                        continue
                    visible_groups[group_id]["memberIds"].append(char_id)
                    characters.append(
                        {
                            "id": char_id,
                            "franchiseId": "imas",
                            "groupId": group_id,
                            "nameZh": member_name,
                            "nameJa": clean_text(str(official["name"])),
                            "hex": row_hex,
                            "sourceUrl": f"https://idollist.idolmaster-official.jp/detail/{official['character_id']}",
                            "imageSourceUrl": resolve_imas_character_image(official),
                            "sourceImageAsset": "",
                            "sortOrder": int(official["character_id"]),
                        }
                    )

    for group in visible_groups.values():
        values = [item["hex"] for item in characters if item["groupId"] == group["id"]]
        if group["id"] == "imas_ds_valiv" and values:
            group["hex"] = average_hex(values)
        elif group["id"] == "imas_other":
            group["hex"] = average_hex(values) if values else overall_brand_hex

    groups = list(visible_groups.values()) + list(extra_groups.values())
    payload = {
        "franchises": [franchise],
        "groups": groups,
        "characters": characters,
    }
    write_json(generated_file("imas.json"), payload)
    return payload


def crawl_vocaloid() -> dict[str, Any]:
    """Build the curated virtual-singer catalog from checked-in source artwork."""
    model = read_json(VOCALOID_CATALOG_PATH)
    franchise = dict(model["franchise"])
    characters: list[dict[str, Any]] = []
    members_by_group: dict[str, list[str]] = defaultdict(list)
    source_root = TOOLS_ROOT / "sources" / "vocaloid" / "originals"
    source_records: list[dict[str, Any]] = []

    for character in model["characters"]:
        source_path = source_root / character["sourceFile"]
        if not source_path.exists():
            raise RuntimeError(f"Missing VOCALOID source artwork: {source_path}")
        crop = character.get("crop", {})
        if set(crop) != {"centerXRatio", "centerYRatio", "sideRatio"}:
            raise RuntimeError(f"Missing explicit face crop: {character['id']}")
        members_by_group[character["groupId"]].append(character["id"])
        characters.append(
            {
                "id": character["id"],
                "franchiseId": franchise["id"],
                "groupId": character["groupId"],
                "nameZh": character["nameZh"],
                "nameJa": character["nameJa"],
                "hex": character["hex"],
                "sourceUrl": character["sourceUrl"],
                "imageSourceUrl": character["imageSourceUrl"],
                "sourceImageAsset": f"tools:sources/vocaloid/originals/{character['sourceFile']}",
                "sortOrder": character["sortOrder"],
            }
        )
        source_records.append(
            {
                "id": character["id"],
                "sourceUrl": character["sourceUrl"],
                "downloadMirror": character["imageSourceUrl"],
                "sourceFile": character["sourceFile"],
                "sha256": hashlib.sha256(source_path.read_bytes()).hexdigest(),
                "colorSource": character["colorSource"],
                "hex": character["hex"],
                "crop": crop,
                "faceReview": "approved-single-face",
            }
        )

    groups: list[dict[str, Any]] = []
    for group in model["groups"]:
        groups.append(
            {
                "id": group["id"],
                "franchiseId": franchise["id"],
                "seriesLabelZh": "分组",
                "seriesLabelJa": "グループ",
                "nameZh": group["nameZh"],
                "nameJa": group["nameJa"],
                "sourceName": group["nameZh"],
                "hex": group["hex"],
                "sourceUrl": group["sourceUrl"],
                "imageSourceUrl": "",
                "sourceImageAsset": group["sourceImageAsset"],
                "groupType": "virtual-singer",
                "sortOrder": group["sortOrder"],
                "memberIds": members_by_group[group["id"]],
                "fallbackText": group["nameZh"],
            }
        )

    payload = {"franchises": [franchise], "groups": groups, "characters": characters}
    write_json(generated_file("vocaloid.json"), payload)
    write_json(
        TOOLS_ROOT / "sources" / "vocaloid" / "manifest.json",
        {
            "retrievedAt": "2026-07-22",
            "usage": "Unofficial, non-commercial character identification for a fan light controller.",
            "characters": source_records,
        },
    )
    return payload


def build_catalog() -> dict[str, Any]:
    ensure_dirs()
    crawl_vocaloid()
    source_files = [
        generated_file("bangdream.json"),
        generated_file("lovelive.json"),
        generated_file("imas.json"),
        generated_file("vocaloid.json"),
    ]
    payloads = [read_json(path) for path in source_files]

    if PALETTE_ROOT.exists():
        shutil.rmtree(PALETTE_ROOT)
    ensure_dirs()

    franchises: list[dict[str, Any]] = []
    groups: list[dict[str, Any]] = []
    characters: list[dict[str, Any]] = []
    report = {"missingCharacterImages": [], "missingGroupImages": [], "emptyGroups": [], "missingLocalizations": []}

    for payload in payloads:
        franchises.extend(payload.get("franchises", []))

        for group in payload.get("groups", []):
            output_name = f"{group['id']}.png"
            output_path = PALETTE_GROUPS_ROOT / output_name
            should_report_group = group["groupType"] not in {"attribute", "unit"}
            saved = save_processed_image(
                output_path,
                source_url=group.get("imageSourceUrl") or None,
                source_asset=group.get("sourceImageAsset") or None,
                referer_url=group.get("sourceUrl") or None,
                mode="group_logo" if group.get("imageKind") == "logo" else "group",
            )
            if not saved:
                make_circle_icon(output_path, group["hex"], group.get("fallbackText", "GRP"))
                if should_report_group:
                    report["missingGroupImages"].append(group["id"])
            groups.append(
                {
                    "id": group["id"],
                    "franchiseId": group["franchiseId"],
                    "seriesLabelZh": clean_text(group.get("seriesLabelZh", "")),
                    "seriesLabelJa": clean_text(group.get("seriesLabelJa", "")),
                    "nameZh": clean_text(group.get("nameZh", "")),
                    "nameJa": clean_text(group.get("nameJa", "")),
                    "sourceName": group["sourceName"],
                    "hex": group["hex"],
                    "image": f"palette/groups/{output_name}",
                    "memberIds": group.get("memberIds", []),
                    "sourceUrl": group["sourceUrl"],
                    "imageSourceUrl": group.get("imageSourceUrl", ""),
                    "groupType": group["groupType"],
                    "imageKind": group.get("imageKind", "avatar"),
                    "sortOrder": group["sortOrder"],
                }
            )
            if should_report_group and not group.get("memberIds"):
                report["emptyGroups"].append(group["id"])
            if not all([clean_text(group.get("seriesLabelZh", "")), clean_text(group.get("seriesLabelJa", "")), clean_text(group.get("nameZh", "")), clean_text(group.get("nameJa", ""))]):
                report["missingLocalizations"].append(group["id"])

        for character in payload.get("characters", []):
            output_name = f"{character['id']}.png"
            output_path = PALETTE_CHARACTERS_ROOT / output_name
            saved = save_processed_image(
                output_path,
                source_url=character.get("imageSourceUrl") or None,
                source_asset=character.get("sourceImageAsset") or None,
                referer_url=character.get("sourceUrl") or None,
                mode="avatar",
                character_id=character.get("id") or None,
                franchise_id=character.get("franchiseId") or None,
            )
            if not saved:
                make_circle_icon(output_path, character["hex"], "?")
                report["missingCharacterImages"].append(character["id"])
            characters.append(
                {
                    "id": character["id"],
                    "franchiseId": character["franchiseId"],
                    "groupId": character["groupId"],
                    "nameZh": clean_text(character.get("nameZh", "")),
                    "nameJa": clean_text(character.get("nameJa", "")),
                    "hex": character["hex"],
                    "image": f"palette/characters/{output_name}",
                    "sourceUrl": character["sourceUrl"],
                    "imageSourceUrl": character.get("imageSourceUrl", ""),
                    "sortOrder": character["sortOrder"],
                }
            )
            if not all([clean_text(character.get("nameZh", "")), clean_text(character.get("nameJa", ""))]):
                report["missingLocalizations"].append(character["id"])

    if report["missingLocalizations"]:
        raise RuntimeError(f"Missing localized names: {report['missingLocalizations'][:20]}")

    catalog = {
        "franchises": sorted(franchises, key=lambda item: item["sortOrder"]),
        "groups": sorted(groups, key=lambda item: (item["franchiseId"], item["sortOrder"], item["nameZh"])),
        "characters": sorted(characters, key=lambda item: (item["franchiseId"], item["groupId"], item["sortOrder"], item["nameZh"])),
    }
    write_json(PALETTE_ROOT / "palette_catalog.json", catalog)
    write_json(generated_file("report.json"), report)
    return catalog


def rebuild_character_assets(franchise_ids: set[str] | None = None) -> dict[str, int]:
    payloads = [
        read_json(generated_file("bangdream.json")),
        read_json(generated_file("lovelive.json")),
        read_json(generated_file("imas.json")),
        read_json(generated_file("vocaloid.json")),
    ]
    processed = 0
    saved = 0
    failed = 0

    for payload in payloads:
        for character in payload.get("characters", []):
            franchise_id = clean_text(character.get("franchiseId", ""))
            if franchise_ids and franchise_id not in franchise_ids:
                continue
            output_name = f"{character['id']}.png"
            output_path = PALETTE_CHARACTERS_ROOT / output_name
            processed += 1
            if save_processed_image(
                output_path,
                source_url=character.get("imageSourceUrl") or None,
                source_asset=character.get("sourceImageAsset") or None,
                referer_url=character.get("sourceUrl") or None,
                mode="avatar",
                character_id=character.get("id") or None,
                franchise_id=franchise_id or None,
            ):
                saved += 1
            else:
                failed += 1

    return {
        "processed": processed,
        "saved": saved,
        "failed": failed,
    }


def main_crawl_bangdream() -> None:
    payload = crawl_bangdream()
    print(f"bangdream: groups={len(payload['groups'])} characters={len(payload['characters'])}")


def main_crawl_lovelive() -> None:
    payload = crawl_lovelive()
    print(f"lovelive: groups={len(payload['groups'])} characters={len(payload['characters'])}")


def main_crawl_imas() -> None:
    payload = crawl_imas()
    print(f"imas: groups={len(payload['groups'])} characters={len(payload['characters'])}")


def main_build_catalog() -> None:
    catalog = build_catalog()
    print(
        "catalog:",
        f"franchises={len(catalog['franchises'])}",
        f"groups={len(catalog['groups'])}",
        f"characters={len(catalog['characters'])}",
    )


def main_rebuild_character_avatars() -> None:
    stats = rebuild_character_assets({"lovelive", "imas"})
    print(
        "avatars:",
        f"processed={stats['processed']}",
        f"saved={stats['saved']}",
        f"failed={stats['failed']}",
    )
