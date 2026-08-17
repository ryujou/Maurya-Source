from __future__ import annotations

import json
import tkinter as tk
from dataclasses import dataclass
from io import BytesIO
from pathlib import Path
from tkinter import ttk
from typing import Any

from PIL import Image, ImageDraw, ImageTk

from palette_pipeline import (
    AVATAR_OVERRIDES_PATH,
    ASSETS_ROOT,
    GENERATED_ROOT,
    fetch_bytes,
    focused_square_crop,
    read_json,
)


CANVAS_SIZE = 520
PREVIEW_SIZE = 160
OUTPUT_SIZE = 96
FIXED_SIDE_RATIO_BY_FRANCHISE = {
    "bangdream": 0.60,
    "lovelive": 0.60,
    "imas": 0.60,
}
DEFAULT_CENTER_Y_BY_FRANCHISE = {
    "bangdream": 0.50,
    "lovelive": 0.30,
    "imas": 0.30,
}
YOLO_MODEL_PATH = Path(r"J:\lumia\Maurya\src\esp32\lumia_esp32_low\lumia_esp32\yolo\best.pt")


@dataclass
class FaceDetection:
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


@dataclass
class CharacterItem:
    id: str
    franchise_id: str
    name_zh: str
    name_ja: str
    source_url: str
    image_source_url: str
    source_image_asset: str
    image_asset: str

    @property
    def display_name(self) -> str:
        return f"{self.franchise_id} | {self.name_zh} | {self.name_ja}"


class AvatarCropEditor:
    def __init__(self) -> None:
        self.root = tk.Tk()
        self.root.title("Peacock Avatar Crop Editor")
        self.root.geometry("1360x900")

        self.items = self._load_items()
        self.overrides = self._load_overrides()

        self.franchise_var = tk.StringVar(value="all")
        self.search_var = tk.StringVar()
        self.search_var.trace_add("write", lambda *_: self.refresh_list())
        self.only_unlabeled_var = tk.BooleanVar(value=False)

        self.center_x_var = tk.DoubleVar(value=0.5)
        self.center_y_var = tk.DoubleVar(value=0.3)
        self.side_ratio_var = tk.DoubleVar(value=0.60)
        self.status_var = tk.StringVar(value="Ready")

        self.filtered_items: list[CharacterItem] = []
        self.current_item: CharacterItem | None = None
        self.original_image: Image.Image | None = None
        self.face_detections: dict[str, FaceDetection | None] = {}
        self.yolo_model: Any | None = None
        self.yolo_load_error: str | None = None
        self.display_scale = 1.0
        self.dragging = False
        self.last_x = 0
        self.last_y = 0
        self.photo_raw: ImageTk.PhotoImage | None = None
        self.photo_square_preview: ImageTk.PhotoImage | None = None
        self.photo_circle_preview: ImageTk.PhotoImage | None = None
        self.pending_detect_item_id: str | None = None

        self._build_ui()
        self._bind_shortcuts()
        self.root.after(0, self.refresh_list)

    def _build_ui(self) -> None:
        self.root.columnconfigure(1, weight=1)
        self.root.rowconfigure(0, weight=1)

        sidebar = ttk.Frame(self.root, padding=12)
        sidebar.grid(row=0, column=0, sticky="ns")
        sidebar.rowconfigure(5, weight=1)

        ttk.Label(sidebar, text="Franchise").grid(row=0, column=0, sticky="w")
        franchise_box = ttk.Combobox(
            sidebar,
            textvariable=self.franchise_var,
            values=["all", "bangdream", "lovelive", "imas"],
            state="readonly",
            width=24,
        )
        franchise_box.grid(row=1, column=0, sticky="ew", pady=(4, 12))
        franchise_box.bind("<<ComboboxSelected>>", lambda *_: self.refresh_list())

        ttk.Label(sidebar, text="Search").grid(row=2, column=0, sticky="w")
        ttk.Entry(sidebar, textvariable=self.search_var, width=28).grid(
            row=3,
            column=0,
            sticky="ew",
            pady=(4, 8),
        )
        ttk.Checkbutton(
            sidebar,
            text="Only unlabeled",
            variable=self.only_unlabeled_var,
            command=self.refresh_list,
        ).grid(row=4, column=0, sticky="w", pady=(0, 8))

        self.listbox = tk.Listbox(sidebar, width=42, height=38)
        self.listbox.grid(row=5, column=0, sticky="nsew")
        self.listbox.bind("<<ListboxSelect>>", self.on_select)

        main = ttk.Frame(self.root, padding=12)
        main.grid(row=0, column=1, sticky="nsew")
        main.columnconfigure(0, weight=1)
        main.columnconfigure(1, weight=0)
        main.rowconfigure(0, weight=1)

        raw_frame = ttk.LabelFrame(main, text="Original Image / Fixed Crop", padding=8)
        raw_frame.grid(row=0, column=0, sticky="nsew", padx=(0, 8))
        raw_frame.columnconfigure(0, weight=1)
        raw_frame.rowconfigure(0, weight=1)

        self.raw_canvas = tk.Canvas(raw_frame, width=CANVAS_SIZE, height=CANVAS_SIZE, bg="#202020")
        self.raw_canvas.grid(row=0, column=0, sticky="nsew")
        self.raw_canvas.bind("<ButtonPress-1>", self.start_drag)
        self.raw_canvas.bind("<B1-Motion>", self.on_drag)
        self.raw_canvas.bind("<ButtonRelease-1>", self.stop_drag)
        self.raw_canvas.bind("<MouseWheel>", self.on_wheel)

        side = ttk.Frame(main)
        side.grid(row=0, column=1, sticky="ns")
        side.columnconfigure(0, weight=1)

        preview_frame = ttk.LabelFrame(side, text="Preview", padding=8)
        preview_frame.grid(row=0, column=0, sticky="ew")
        preview_frame.columnconfigure((0, 1), weight=1)

        ttk.Label(preview_frame, text="96x96 Square").grid(row=0, column=0, sticky="w")
        ttk.Label(preview_frame, text="Circle Look").grid(row=0, column=1, sticky="w")

        self.square_preview_label = ttk.Label(preview_frame)
        self.square_preview_label.grid(row=1, column=0, padx=(0, 8), pady=(8, 0))
        self.circle_preview_label = ttk.Label(preview_frame)
        self.circle_preview_label.grid(row=1, column=1, pady=(8, 0))

        info_frame = ttk.LabelFrame(side, text="Info", padding=8)
        info_frame.grid(row=1, column=0, sticky="ew", pady=(12, 0))
        self.info_label = ttk.Label(info_frame, text="", wraplength=360, justify="left")
        self.info_label.grid(row=0, column=0, sticky="w")

        help_frame = ttk.LabelFrame(side, text="Shortcuts", padding=8)
        help_frame.grid(row=2, column=0, sticky="ew", pady=(12, 0))
        ttk.Label(
            help_frame,
            justify="left",
            text=(
                "Drag: move crop\n"
                "Mouse wheel: zoom crop\n"
                "Up / Down: previous / next character\n"
                "Ctrl+S: save override\n"
                "D: save and next\n"
                "Delete: delete override\n"
                "R: reset to default center"
            ),
        ).grid(row=0, column=0, sticky="w")

        zoom_frame = ttk.LabelFrame(side, text="Crop Size", padding=8)
        zoom_frame.grid(row=3, column=0, sticky="ew", pady=(12, 0))
        zoom_frame.columnconfigure(0, weight=1)
        self.zoom_scale = ttk.Scale(
            zoom_frame,
            from_=0.35,
            to=0.90,
            variable=self.side_ratio_var,
            command=lambda _value: self.render(),
        )
        self.zoom_scale.grid(row=0, column=0, sticky="ew")
        self.zoom_value_label = ttk.Label(zoom_frame, text="")
        self.zoom_value_label.grid(row=1, column=0, sticky="e", pady=(6, 0))

        buttons = ttk.Frame(side)
        buttons.grid(row=4, column=0, sticky="ew", pady=(12, 0))
        buttons.columnconfigure((0, 1, 2, 3, 4), weight=1)
        ttk.Button(buttons, text="Reset", command=self.reset_to_default).grid(row=0, column=0, sticky="ew")
        ttk.Button(buttons, text="Save", command=self.save_override).grid(row=0, column=1, sticky="ew", padx=8)
        ttk.Button(buttons, text="Delete", command=self.delete_override).grid(row=0, column=2, sticky="ew")
        ttk.Button(buttons, text="Next", command=lambda: self.select_relative(1)).grid(
            row=0,
            column=3,
            sticky="ew",
            padx=(8, 0),
        )
        ttk.Button(buttons, text="Save+Next", command=self.save_and_next).grid(
            row=0,
            column=4,
            sticky="ew",
            padx=(8, 0),
        )

        ttk.Label(side, textvariable=self.status_var, wraplength=360, justify="left").grid(
            row=5,
            column=0,
            sticky="ew",
            pady=(12, 0),
        )

    def _bind_shortcuts(self) -> None:
        self.root.bind_all("<Control-s>", lambda _event: self.save_override())
        self.root.bind_all("<Delete>", lambda _event: self.delete_override())
        self.root.bind_all("<r>", lambda _event: self.reset_to_default())
        self.root.bind_all("<R>", lambda _event: self.reset_to_default())
        self.root.bind_all("<Up>", lambda _event: self.select_relative(-1))
        self.root.bind_all("<Down>", lambda _event: self.select_relative(1))
        self.root.bind_all("<d>", lambda _event: self.save_and_next())
        self.root.bind_all("<D>", lambda _event: self.save_and_next())

    def _load_items(self) -> list[CharacterItem]:
        items: list[CharacterItem] = []
        for file_name in ("bangdream.json", "lovelive.json", "imas.json"):
            payload = read_json(GENERATED_ROOT / file_name)
            for character in payload.get("characters", []):
                items.append(
                    CharacterItem(
                        id=character["id"],
                        franchise_id=character["franchiseId"],
                        name_zh=character.get("nameZh") or character.get("name") or "",
                        name_ja=character.get("nameJa") or character.get("name") or "",
                        source_url=character.get("sourceUrl", ""),
                        image_source_url=character.get("imageSourceUrl", ""),
                        source_image_asset=character.get("sourceImageAsset", ""),
                        image_asset=character.get("image", ""),
                    )
                )
        return items

    def _load_overrides(self) -> dict[str, dict[str, float]]:
        if not AVATAR_OVERRIDES_PATH.exists():
            return {}
        return read_json(AVATAR_OVERRIDES_PATH)

    def refresh_list(self, preferred_index: int = 0) -> None:
        franchise = self.franchise_var.get()
        keyword = self.search_var.get().strip().lower()
        self.filtered_items = [
            item for item in self.items
            if (franchise == "all" or item.franchise_id == franchise)
            and (not keyword or keyword in item.display_name.lower())
            and (not self.only_unlabeled_var.get() or item.id not in self.overrides)
        ]
        self.listbox.delete(0, tk.END)
        for item in self.filtered_items:
            self.listbox.insert(tk.END, item.display_name)
        if self.filtered_items:
            self._select_index(preferred_index)
        else:
            self.current_item = None
            self.original_image = None
            self.raw_canvas.delete("all")
            self.square_preview_label.configure(image="")
            self.circle_preview_label.configure(image="")
            self.info_label.configure(text="")
            self.status_var.set(self.list_status_text("No matching characters"))

    def list_status_text(self, prefix: str) -> str:
        labeled_count = len(self.overrides)
        return (
            f"{prefix}\n"
            f"visible={len(self.filtered_items)} / total={len(self.items)} / labeled={labeled_count}"
        )

    def _select_index(self, index: int) -> None:
        if not self.filtered_items:
            return
        clamped = max(0, min(index, len(self.filtered_items) - 1))
        self.listbox.selection_clear(0, tk.END)
        self.listbox.selection_set(clamped)
        self.listbox.activate(clamped)
        self.listbox.see(clamped)
        self.on_select()

    def select_relative(self, delta: int) -> None:
        if not self.filtered_items:
            return
        if self.listbox.curselection():
            index = int(self.listbox.curselection()[0]) + delta
        else:
            index = 0
        self._select_index(index)

    def on_select(self, *_args) -> None:
        if not self.listbox.curselection():
            return
        index = int(self.listbox.curselection()[0])
        self.current_item = self.filtered_items[index]
        try:
            self.original_image = self.load_original_image(self.current_item)
        except Exception as exc:
            self.original_image = None
            self.raw_canvas.delete("all")
            self.square_preview_label.configure(image="")
            self.circle_preview_label.configure(image="")
            self.info_label.configure(text=self.current_item.display_name)
            self.status_var.set(self.list_status_text(f"Failed to load image: {exc}"))
            return
        self.apply_current_override()
        self.render()
        self.schedule_face_detection()

    def schedule_face_detection(self) -> None:
        if not self.current_item:
            return
        item_id = self.current_item.id
        if item_id in self.face_detections:
            return
        self.pending_detect_item_id = item_id
        self.status_var.set(self.list_status_text(f"Loading {item_id}"))
        self.root.after(1, self.detect_face_for_current_item)

    def load_original_image(self, item: CharacterItem) -> Image.Image:
        local_asset_path = self.resolve_local_asset_path(item.source_image_asset)
        if local_asset_path and local_asset_path.exists():
            return Image.open(local_asset_path).convert("RGBA")

        try:
            payload = fetch_bytes(item.image_source_url, referer_url=item.source_url)
            return Image.open(BytesIO(payload)).convert("RGBA")
        except Exception:
            fallback_asset_path = self.resolve_local_asset_path(item.image_asset)
            if fallback_asset_path and fallback_asset_path.exists():
                return Image.open(fallback_asset_path).convert("RGBA")
            raise

    def resolve_local_asset_path(self, asset_ref: str) -> Path | None:
        cleaned = (asset_ref or "").strip().replace("\\", "/")
        if not cleaned:
            return None
        if cleaned.startswith("assets/"):
            cleaned = cleaned[len("assets/") :]
        return ASSETS_ROOT / Path(cleaned)

    def fixed_side_ratio(self) -> float:
        franchise_id = self.current_item.franchise_id if self.current_item else "bangdream"
        return FIXED_SIDE_RATIO_BY_FRANCHISE.get(franchise_id, 0.60)

    def default_center_y(self) -> float:
        franchise_id = self.current_item.franchise_id if self.current_item else "bangdream"
        return DEFAULT_CENTER_Y_BY_FRANCHISE.get(franchise_id, 0.50)

    def apply_current_override(self) -> None:
        if not self.current_item:
            return
        override = self.overrides.get(self.current_item.id)
        if override:
            self.center_x_var.set(float(override["centerXRatio"]))
            self.center_y_var.set(float(override["centerYRatio"]))
            self.side_ratio_var.set(float(override.get("sideRatio", self.fixed_side_ratio())))
            self.status_var.set(self.list_status_text(f"Loaded override for {self.current_item.id}"))
            return

        self.center_x_var.set(0.5)
        self.center_y_var.set(self.default_center_y())
        self.side_ratio_var.set(self.fixed_side_ratio())
        self.status_var.set(self.list_status_text(f"Using default center for {self.current_item.id}"))

    def load_yolo_model(self) -> Any | None:
        if self.yolo_model is not None:
            return self.yolo_model
        if self.yolo_load_error:
            return None
        if not YOLO_MODEL_PATH.exists():
            self.yolo_load_error = f"YOLO model not found: {YOLO_MODEL_PATH}"
            return None

        try:
            import pathlib

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
            self.yolo_model = YOLO(str(YOLO_MODEL_PATH))
            return self.yolo_model
        except Exception as exc:
            self.yolo_load_error = f"{type(exc).__name__}: {exc}"
            return None

    def detect_face_for_current_item(self) -> None:
        if not self.current_item or not self.original_image:
            return
        if self.current_item.id in self.face_detections:
            return
        if self.pending_detect_item_id and self.current_item.id != self.pending_detect_item_id:
            return

        model = self.load_yolo_model()
        if model is None:
            self.face_detections[self.current_item.id] = None
            self.pending_detect_item_id = None
            self.render()
            return

        try:
            results = model.predict(
                source=self.original_image.convert("RGB"),
                verbose=False,
                imgsz=640,
                conf=0.15,
                max_det=5,
                device="cpu",
            )
            boxes = results[0].boxes if results else None
            if boxes is None or len(boxes) == 0:
                self.face_detections[self.current_item.id] = None
                self.pending_detect_item_id = None
                self.render()
                return

            xyxy_values = boxes.xyxy.cpu().tolist()
            conf_values = boxes.conf.cpu().tolist() if boxes.conf is not None else [0.0] * len(xyxy_values)
            detections = [
                FaceDetection(
                    left=float(xyxy[0]),
                    top=float(xyxy[1]),
                    right=float(xyxy[2]),
                    bottom=float(xyxy[3]),
                    confidence=float(confidence),
                )
                for xyxy, confidence in zip(xyxy_values, conf_values, strict=False)
            ]
            self.face_detections[self.current_item.id] = max(
                detections,
                key=lambda detection: (detection.confidence, detection.area),
            )
        except Exception as exc:
            self.yolo_load_error = f"{type(exc).__name__}: {exc}"
            self.face_detections[self.current_item.id] = None
        self.pending_detect_item_id = None
        self.render()

    def current_face_detection(self) -> FaceDetection | None:
        if not self.current_item:
            return None
        return self.face_detections.get(self.current_item.id)

    def clamp_center_ratios(self, center_x_ratio: float, center_y_ratio: float) -> tuple[float, float]:
        if not self.original_image:
            return center_x_ratio, center_y_ratio

        width, height = self.original_image.size
        side = min(width, height) * float(self.side_ratio_var.get())
        half_side = side / 2.0

        min_x_ratio = half_side / width
        max_x_ratio = 1.0 - min_x_ratio
        min_y_ratio = half_side / height
        max_y_ratio = 1.0 - min_y_ratio

        return (
            min(max(center_x_ratio, min_x_ratio), max_x_ratio),
            min(max(center_y_ratio, min_y_ratio), max_y_ratio),
        )

    def render(self) -> None:
        if not self.current_item or not self.original_image:
            return

        width, height = self.original_image.size
        display = self.original_image.copy()
        display.thumbnail((CANVAS_SIZE, CANVAS_SIZE), Image.Resampling.LANCZOS)
        self.display_scale = display.width / width
        self.photo_raw = ImageTk.PhotoImage(display)
        self.raw_canvas.delete("all")
        self.raw_canvas.create_image(0, 0, anchor="nw", image=self.photo_raw)

        side_ratio = float(self.side_ratio_var.get())
        side = min(width, height) * side_ratio
        center_x_ratio, center_y_ratio = self.clamp_center_ratios(
            float(self.center_x_var.get()),
            float(self.center_y_var.get()),
        )
        self.center_x_var.set(center_x_ratio)
        self.center_y_var.set(center_y_ratio)
        center_x = width * center_x_ratio
        center_y = height * center_y_ratio

        left = (center_x - side / 2) * self.display_scale
        top = (center_y - side / 2) * self.display_scale
        right = (center_x + side / 2) * self.display_scale
        bottom = (center_y + side / 2) * self.display_scale
        detection = self.current_face_detection()
        if detection is not None:
            face_left = detection.left * self.display_scale
            face_top = detection.top * self.display_scale
            face_right = detection.right * self.display_scale
            face_bottom = detection.bottom * self.display_scale
            self.raw_canvas.create_rectangle(
                face_left,
                face_top,
                face_right,
                face_bottom,
                outline="#FF6B6B",
                width=2,
            )
            self.raw_canvas.create_text(
                face_left + 6,
                max(10, face_top - 8),
                anchor="sw",
                fill="#FFB0B0",
                text=f"face {detection.confidence:.2f}",
                font=("Segoe UI", 10, "bold"),
            )
        self.raw_canvas.create_rectangle(left, top, right, bottom, outline="#5FD6FF", width=3)

        square_preview = focused_square_crop(
            self.original_image,
            center_x=center_x,
            center_y=center_y,
            side=side,
            size=OUTPUT_SIZE,
        )
        square_preview_large = square_preview.resize((PREVIEW_SIZE, PREVIEW_SIZE), Image.Resampling.NEAREST)
        circle_preview_large = self.make_circle_preview(square_preview_large)

        self.photo_square_preview = ImageTk.PhotoImage(square_preview_large)
        self.photo_circle_preview = ImageTk.PhotoImage(circle_preview_large)
        self.square_preview_label.configure(image=self.photo_square_preview)
        self.circle_preview_label.configure(image=self.photo_circle_preview)

        self.info_label.configure(
            text=(
                f"{self.current_item.display_name}\n"
                f"id={self.current_item.id}\n"
                f"centerXRatio={self.center_x_var.get():.4f}\n"
                f"centerYRatio={self.center_y_var.get():.4f}\n"
                f"sideRatio={side_ratio:.4f}\n"
                f"face={self.format_face_detection(detection)}"
            )
        )
        self.zoom_value_label.configure(text=f"sideRatio={side_ratio:.4f}")

    def format_face_detection(self, detection: FaceDetection | None) -> str:
        if detection is not None:
            return (
                f"{detection.left:.1f},{detection.top:.1f} -> "
                f"{detection.right:.1f},{detection.bottom:.1f} "
                f"(conf={detection.confidence:.2f})"
            )
        if self.yolo_load_error:
            return f"unavailable ({self.yolo_load_error})"
        if not YOLO_MODEL_PATH.exists():
            return "unavailable (model not found)"
        return "not found"

    def make_circle_preview(self, image: Image.Image) -> Image.Image:
        masked = image.convert("RGBA")
        mask = Image.new("L", masked.size, 0)
        draw = ImageDraw.Draw(mask)
        draw.ellipse((0, 0, masked.width - 1, masked.height - 1), fill=255)
        masked.putalpha(mask)
        background = Image.new("RGBA", masked.size, (32, 32, 32, 255))
        background.alpha_composite(masked)
        return background

    def start_drag(self, event: tk.Event) -> None:
        if not self.current_item or not self.original_image:
            return
        self.dragging = True
        self.last_x = event.x
        self.last_y = event.y

    def on_drag(self, event: tk.Event) -> None:
        if not self.dragging or not self.current_item or not self.original_image:
            return
        dx = (event.x - self.last_x) / max(self.display_scale, 1e-6) / self.original_image.width
        dy = (event.y - self.last_y) / max(self.display_scale, 1e-6) / self.original_image.height
        center_x_ratio, center_y_ratio = self.clamp_center_ratios(
            self.center_x_var.get() + dx,
            self.center_y_var.get() + dy,
        )
        self.center_x_var.set(center_x_ratio)
        self.center_y_var.set(center_y_ratio)
        self.last_x = event.x
        self.last_y = event.y
        self.render()

    def on_wheel(self, event: tk.Event) -> None:
        if not self.current_item or not self.original_image:
            return
        step = 0.03 if event.delta > 0 else -0.03
        next_value = min(0.90, max(0.35, float(self.side_ratio_var.get()) + step))
        self.side_ratio_var.set(next_value)
        center_x_ratio, center_y_ratio = self.clamp_center_ratios(
            float(self.center_x_var.get()),
            float(self.center_y_var.get()),
        )
        self.center_x_var.set(center_x_ratio)
        self.center_y_var.set(center_y_ratio)
        self.render()

    def stop_drag(self, _event: tk.Event) -> None:
        self.dragging = False

    def reset_to_default(self) -> None:
        if not self.current_item:
            return
        self.overrides.pop(self.current_item.id, None)
        self.center_x_var.set(0.5)
        self.center_y_var.set(self.default_center_y())
        self.side_ratio_var.set(self.fixed_side_ratio())
        self.status_var.set(f"Reset to default center for {self.current_item.id}")
        self.render()

    def save_override(self) -> None:
        if not self.current_item:
            return
        self.overrides[self.current_item.id] = {
            "centerXRatio": round(float(self.center_x_var.get()), 6),
            "centerYRatio": round(float(self.center_y_var.get()), 6),
            "sideRatio": round(float(self.side_ratio_var.get()), 6),
        }
        AVATAR_OVERRIDES_PATH.write_text(
            json.dumps(dict(sorted(self.overrides.items())), ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        self.status_var.set(self.list_status_text(f"Saved override for {self.current_item.id}"))

    def save_and_next(self) -> None:
        if not self.current_item:
            return
        current_id = self.current_item.id
        current_index = int(self.listbox.curselection()[0]) if self.listbox.curselection() else 0
        self.save_override()
        next_index = current_index if self.only_unlabeled_var.get() else current_index + 1
        self.refresh_list(preferred_index=next_index)
        if not self.filtered_items:
            self.status_var.set(self.list_status_text(f"Saved override for {current_id}; no more items"))
            return
        self.status_var.set(self.list_status_text(f"Saved override for {current_id}; moved to next item"))

    def delete_override(self) -> None:
        if not self.current_item:
            return
        self.overrides.pop(self.current_item.id, None)
        AVATAR_OVERRIDES_PATH.write_text(
            json.dumps(dict(sorted(self.overrides.items())), ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        self.center_x_var.set(0.5)
        self.center_y_var.set(self.default_center_y())
        self.side_ratio_var.set(self.fixed_side_ratio())
        self.status_var.set(self.list_status_text(f"Deleted override for {self.current_item.id}"))
        self.render()

    def run(self) -> None:
        self.root.mainloop()


if __name__ == "__main__":
    AvatarCropEditor().run()
