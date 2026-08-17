from __future__ import annotations

import json
import pathlib
from dataclasses import dataclass
from io import BytesIO
from pathlib import Path
from typing import Any

from PIL import Image

from palette_pipeline import (
    ASSETS_ROOT,
    AVATAR_OVERRIDES_PATH,
    GENERATED_ROOT,
    fetch_bytes,
    read_json,
)


YOLO_MODEL_PATH = Path(r"J:\lumia\Maurya\src\esp32\lumia_esp32_low\lumia_esp32\yolo\best.pt")
GENERATED_FILES = ("bangdream.json", "lovelive.json", "imas.json")
FIXED_SIDE_RATIO_BY_FRANCHISE = {
    "bangdream": 0.60,
    "lovelive": 0.60,
    "imas": 0.60,
}


@dataclass
class CharacterItem:
    id: str
    franchise_id: str
    source_url: str
    image_source_url: str
    source_image_asset: str
    image_asset: str


@dataclass
class Detection:
    left: float
    top: float
    right: float
    bottom: float
    confidence: float

    @property
    def center_x(self) -> float:
        return (self.left + self.right) / 2.0

    @property
    def center_y(self) -> float:
        return (self.top + self.bottom) / 2.0

    @property
    def area(self) -> float:
        return max(0.0, self.right - self.left) * max(0.0, self.bottom - self.top)


def safe_import_yolo() -> Any:
    original_exists = pathlib.Path.exists

    def safe_exists(path: pathlib.Path) -> bool:
        try:
            return original_exists(path)
        except OSError as exc:
            if getattr(exc, "winerror", None) == 1337:
                return False
            raise

    pathlib.Path.exists = safe_exists
    try:
        from ultralytics import YOLO  # type: ignore
    finally:
        pathlib.Path.exists = original_exists
    return YOLO


def load_items() -> list[CharacterItem]:
    items: list[CharacterItem] = []
    for file_name in GENERATED_FILES:
        payload = read_json(GENERATED_ROOT / file_name)
        for character in payload.get("characters", []):
            items.append(
                CharacterItem(
                    id=character["id"],
                    franchise_id=character["franchiseId"],
                    source_url=character.get("sourceUrl", ""),
                    image_source_url=character.get("imageSourceUrl", ""),
                    source_image_asset=character.get("sourceImageAsset", ""),
                    image_asset=character.get("image", ""),
                )
            )
    return items


def resolve_local_asset_path(asset_ref: str) -> Path | None:
    cleaned = (asset_ref or "").strip().replace("\\", "/")
    if not cleaned:
        return None
    if cleaned.startswith("assets/"):
        cleaned = cleaned[len("assets/") :]
    return ASSETS_ROOT / Path(cleaned)


def load_original_image(item: CharacterItem) -> Image.Image:
    local_asset_path = resolve_local_asset_path(item.source_image_asset)
    if local_asset_path and local_asset_path.exists():
        return Image.open(local_asset_path).convert("RGBA")

    try:
        payload = fetch_bytes(item.image_source_url, referer_url=item.source_url)
        return Image.open(BytesIO(payload)).convert("RGBA")
    except Exception:
        fallback_asset_path = resolve_local_asset_path(item.image_asset)
        if fallback_asset_path and fallback_asset_path.exists():
            return Image.open(fallback_asset_path).convert("RGBA")
        raise


def clamp_center_ratios(franchise_id: str, width: int, height: int, center_x_ratio: float, center_y_ratio: float) -> tuple[float, float]:
    side = min(width, height) * FIXED_SIDE_RATIO_BY_FRANCHISE.get(franchise_id, 0.60)
    half_side = side / 2.0
    min_x_ratio = half_side / width
    max_x_ratio = 1.0 - min_x_ratio
    min_y_ratio = half_side / height
    max_y_ratio = 1.0 - min_y_ratio
    return (
        min(max(center_x_ratio, min_x_ratio), max_x_ratio),
        min(max(center_y_ratio, min_y_ratio), max_y_ratio),
    )


def detect_largest_face(model: Any, image: Image.Image) -> Detection | None:
    results = model.predict(
        source=image.convert("RGB"),
        verbose=False,
        imgsz=640,
        conf=0.15,
        max_det=8,
        device="cpu",
    )
    boxes = results[0].boxes if results else None
    if boxes is None or len(boxes) == 0:
        return None

    xyxy_values = boxes.xyxy.cpu().tolist()
    conf_values = boxes.conf.cpu().tolist() if boxes.conf is not None else [0.0] * len(xyxy_values)
    detections = [
        Detection(
            left=float(xyxy[0]),
            top=float(xyxy[1]),
            right=float(xyxy[2]),
            bottom=float(xyxy[3]),
            confidence=float(confidence),
        )
        for xyxy, confidence in zip(xyxy_values, conf_values, strict=False)
    ]
    return max(detections, key=lambda detection: detection.area)


def main() -> None:
    if not YOLO_MODEL_PATH.exists():
        raise FileNotFoundError(f"YOLO model not found: {YOLO_MODEL_PATH}")

    YOLO = safe_import_yolo()
    model = YOLO(str(YOLO_MODEL_PATH))
    items = load_items()
    existing_overrides = read_json(AVATAR_OVERRIDES_PATH) if AVATAR_OVERRIDES_PATH.exists() else {}
    overrides = dict(existing_overrides)

    detected_count = 0
    missing_count = 0
    failed_items: list[str] = []

    for index, item in enumerate(items, start=1):
        try:
            image = load_original_image(item)
            detection = detect_largest_face(model, image)
            if detection is None:
                missing_count += 1
                continue

            width, height = image.size
            center_x_ratio = detection.center_x / width
            center_y_ratio = detection.center_y / height
            center_x_ratio, center_y_ratio = clamp_center_ratios(
                item.franchise_id,
                width,
                height,
                center_x_ratio,
                center_y_ratio,
            )
            overrides[item.id] = {
                "centerXRatio": round(center_x_ratio, 6),
                "centerYRatio": round(center_y_ratio, 6),
                "sideRatio": round(FIXED_SIDE_RATIO_BY_FRANCHISE.get(item.franchise_id, 0.60), 6),
            }
            detected_count += 1
        except Exception as exc:
            failed_items.append(f"{item.id}: {type(exc).__name__}: {exc}")

        if index % 25 == 0:
            print(f"[{index}/{len(items)}] detected={detected_count} missing={missing_count} failed={len(failed_items)}")

    AVATAR_OVERRIDES_PATH.write_text(
        json.dumps(dict(sorted(overrides.items())), ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    report = {
        "total": len(items),
        "detected": detected_count,
        "missing": missing_count,
        "failed": failed_items,
        "overridesWritten": len(overrides),
    }
    report_path = GENERATED_ROOT / "auto_detect_avatar_overrides_report.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"done total={len(items)} detected={detected_count} missing={missing_count} failed={len(failed_items)}")
    print(f"overrides={AVATAR_OVERRIDES_PATH}")
    print(f"report={report_path}")


if __name__ == "__main__":
    main()
