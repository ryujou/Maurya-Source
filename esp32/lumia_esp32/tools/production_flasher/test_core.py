from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

from production_flasher.core import (
    DeviceInfo,
    ProductionError,
    VERSION,
    candidate_ports,
    localized,
    parse_probe_output,
    require_single_port,
    run_production,
    validate_modbus_response,
    verify_images,
)


class FakeBackend:
    def __init__(self, failure: str | None = None):
        self.failure = failure
        self.calls = []

    def _call(self, stage):
        self.calls.append(stage)
        if self.failure == stage:
            raise RuntimeError(f"{stage} failed")

    def probe(self, port):
        self._call("probe")
        return DeviceInfo(port, "14:63:93:B3:49:3C", "46:4016", "4MB")

    def erase(self, port): self._call("erase")
    def write(self, port, images): self._call("write")
    def verify_application(self, port): self._call("verify")


def make_firmware(directory: Path, corrupt: bool = False) -> Path:
    addresses = (0x0, 0x8000, 0x20000, 0x240000)
    images = []
    for index, address in enumerate(addresses):
        name = f"image-{index}.bin"
        payload = bytes([index + 1]) * (16 + index)
        (directory / name).write_bytes(payload + (b"bad" if corrupt and index == 2 else b""))
        images.append({
            "file": name,
            "address": hex(address),
            "size": len(payload),
            "sha256": hashlib.sha256(payload).hexdigest(),
        })
    (directory / "flash-manifest.json").write_text(
        json.dumps({"version": VERSION, "images": images}), encoding="utf-8"
    )
    return directory


class ProductionFlasherTests(unittest.TestCase):
    def test_port_detection_zero_one_multiple(self):
        ordinary = SimpleNamespace(device="COM1", vid=None)
        esp = SimpleNamespace(device="COM4", vid=0x303A)
        esp2 = SimpleNamespace(device="COM5", vid=0x303A)
        self.assertEqual(candidate_ports([ordinary, esp]), ["COM4"])
        with self.assertRaises(ProductionError): require_single_port([ordinary])
        with self.assertRaises(ProductionError): require_single_port([esp, esp2])

    def test_probe_rejects_wrong_chip_and_flash(self):
        good_chip = "Chip type: ESP32-C3\nMAC: 14:63:93:b3:49:3c"
        good_flash = "Manufacturer: 46\nDevice: 4016\nDetected flash size: 4MB"
        info = parse_probe_output("COM4", good_chip, good_flash)
        self.assertEqual(info.mac, "14:63:93:B3:49:3C")
        with self.assertRaises(ProductionError): parse_probe_output("COM4", "ESP32-S3", good_flash)
        with self.assertRaises(ProductionError): parse_probe_output("COM4", good_chip, "Detected flash size: 2MB")

    def test_manifest_hash_rejection(self):
        with tempfile.TemporaryDirectory() as name:
            directory = make_firmware(Path(name), corrupt=True)
            with self.assertRaises(ProductionError): verify_images(directory)

    def test_modbus_response_and_crc_rejection(self):
        validate_modbus_response(bytes.fromhex("01030200017984"))
        with self.assertRaises(ProductionError): validate_modbus_response(bytes.fromhex("01030200017985"))
        with self.assertRaises(ProductionError): validate_modbus_response(b"")

    def test_success_and_failure_stages_stop_immediately(self):
        with tempfile.TemporaryDirectory() as name:
            directory = make_firmware(Path(name))
            backend = FakeBackend()
            result = run_production("COM4", directory, backend, lambda *_: None)
            self.assertEqual(result.device.flash_size, "4MB")
            self.assertEqual(backend.calls, ["probe", "erase", "write", "verify"])
            expected_stage = {
                "probe": "芯片检测", "erase": "整片擦除",
                "write": "固件烧录", "verify": "启动验证",
            }
            for failure in expected_stage:
                failed = FakeBackend(failure)
                with self.assertRaises(ProductionError) as context:
                    run_production("COM4", directory, failed, lambda *_: None)
                self.assertEqual(context.exception.stage, expected_stage[failure])
                self.assertEqual(failed.calls[-1], failure)

    def test_variant_localization(self):
        self.assertEqual(localized("中文", "日本語", "multilingual"), "中文")
        self.assertEqual(localized("中文", "日本語", "ja"), "日本語")


if __name__ == "__main__":
    unittest.main()
