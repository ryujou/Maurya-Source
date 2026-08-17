from __future__ import annotations

import csv
import json
from pathlib import Path


FLASH_SIZE = 4 * 1024 * 1024
EXPECTED = {
    "nvs": (0x9000, 0x6000),
    "otadata": (0xF000, 0x2000),
    "phy_init": (0x11000, 0x1000),
    "lumiacfg": (0x12000, 0x4000),
    "ota_0": (0x20000, 0x110000),
    "ota_1": (0x130000, 0x110000),
    "assetsfs": (0x240000, 0x1C0000),
}


def parse_number(value: str) -> int:
    value = value.strip().upper()
    multiplier = 1
    if value.endswith("K"):
        value, multiplier = value[:-1], 1024
    elif value.endswith("M"):
        value, multiplier = value[:-1], 1024 * 1024
    return int(value, 0) * multiplier


def load_partitions(path: Path) -> dict[str, tuple[int, int]]:
    rows: dict[str, tuple[int, int]] = {}
    with path.open(encoding="utf-8", newline="") as handle:
        for row in csv.reader(line for line in handle if not line.lstrip().startswith("#")):
            if not row or not row[0].strip():
                continue
            rows[row[0].strip()] = (parse_number(row[3]), parse_number(row[4]))
    return rows


def main() -> None:
    project = Path(__file__).resolve().parents[1]
    partitions = load_partitions(project / "partitions.csv")
    assert partitions == EXPECTED, partitions

    ordered = sorted((offset, offset + size, name) for name, (offset, size) in partitions.items())
    for previous, current in zip(ordered, ordered[1:]):
        assert previous[1] <= current[0], f"partition overlap: {previous[2]} and {current[2]}"
    assert max(end for _, end, _ in ordered) == FLASH_SIZE
    assert partitions["ota_0"][0] % 0x10000 == 0
    assert partitions["ota_1"][0] % 0x10000 == 0

    defaults = (project / "sdkconfig.defaults").read_text(encoding="utf-8")
    assert "CONFIG_ESPTOOLPY_FLASHSIZE_4MB=y" in defaults
    assert "CONFIG_ESPTOOLPY_FLASHSIZE_2MB=y" not in defaults

    ble_transport = (
        project / "components" / "lumia_platform" / "ble_transport.c"
    ).read_text(encoding="utf-8")
    web_server = (
        project / "components" / "lumia_web" / "web_server.c"
    ).read_text(encoding="utf-8")
    for source in (ble_transport, web_server):
        assert "CONFIG_LUMIA_WIFI_AP_SSID_PREFIX" in source
        assert "ESP_MAC_WIFI_SOFTAP" in source
        assert '"%s-%02X%02X"' in source

    build = project / "build_ota"
    image = build / "lumia_esp32.bin"
    assetsfs = build / "assetsfs.bin"
    args = build / "flasher_args.json"
    if image.exists():
        assert image.stat().st_size <= int(EXPECTED["ota_0"][1] * 0.9)
    if assetsfs.exists():
        assert assetsfs.stat().st_size == EXPECTED["assetsfs"][1]
    if args.exists():
        flasher = json.loads(args.read_text(encoding="utf-8"))
        assert flasher["flash_settings"]["flash_size"] in {"keep", "4MB"}
        assert flasher["flash_files"]["0x20000"] == "lumia_esp32.bin"
        assert flasher["flash_files"]["0x240000"] == "assetsfs.bin"
    print("flash layout tests passed")


if __name__ == "__main__":
    main()
