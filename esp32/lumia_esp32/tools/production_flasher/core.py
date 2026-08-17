from __future__ import annotations

import contextlib
import hashlib
import io
import json
import os
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterable, Protocol

import esptool
import serial
from serial.tools import list_ports


VERSION = os.environ.get("MAURYA_FIRMWARE_VERSION", "1.6.0")
VARIANT = os.environ.get("MAURYA_FIRMWARE_VARIANT", "multilingual")
JAPANESE_ONLY = VARIANT == "ja"
USB_VID = 0x303A
EXPECTED_CHIP = "ESP32-C3"
EXPECTED_FLASH = "4MB"
DEFAULT_BAUD = "460800"
MODBUS_REQUEST = bytes.fromhex("010300000001840A")


def localized(zh: str, ja: str, variant: str | None = None) -> str:
    return ja if (VARIANT if variant is None else variant) == "ja" else zh


class ProductionError(RuntimeError):
    def __init__(self, stage: str, message: str):
        super().__init__(message)
        self.stage = stage


@dataclass(frozen=True)
class DeviceInfo:
    port: str
    mac: str
    flash_id: str
    flash_size: str


@dataclass(frozen=True)
class FlashImage:
    name: str
    address: int
    size: int
    sha256: str


@dataclass(frozen=True)
class ProductionResult:
    device: DeviceInfo
    elapsed_seconds: float


ProgressCallback = Callable[[str, int, str], None]


class FlashBackend(Protocol):
    def probe(self, port: str) -> DeviceInfo: ...
    def erase(self, port: str) -> None: ...
    def write(self, port: str, images: list[tuple[int, Path]]) -> None: ...
    def verify_application(self, port: str) -> None: ...


def candidate_ports(ports: Iterable[object] | None = None) -> list[str]:
    source = list_ports.comports() if ports is None else ports
    return sorted(
        str(item.device)
        for item in source
        if getattr(item, "vid", None) == USB_VID
    )


def require_single_port(ports: Iterable[object] | None = None) -> str:
    found = candidate_ports(ports)
    if not found:
        raise ProductionError(localized("设备检测", "デバイス検出"), localized(
            "未找到USB VID 303A的ESP32-C3",
            "USB VID 303AのESP32-C3が見つかりません",
        ))
    if len(found) > 1:
        raise ProductionError(localized("设备检测", "デバイス検出"), localized(
            f"检测到多个设备：{', '.join(found)}。请只连接一块控制板",
            f"複数のデバイスが見つかりました：{', '.join(found)}。基板は1台だけ接続してください",
        ))
    return found[0]


def modbus_crc16(data: bytes) -> int:
    value = 0xFFFF
    for byte in data:
        value ^= byte
        for _ in range(8):
            value = (value >> 1) ^ 0xA001 if value & 1 else value >> 1
    return value


def validate_modbus_response(data: bytes) -> None:
    if len(data) != 7:
        raise ProductionError(localized("启动验证", "起動確認"), localized(
            f"Modbus响应长度不正确：{len(data)}",
            f"Modbus応答の長さが不正です：{len(data)}",
        ))
    if modbus_crc16(data[:-2]) != int.from_bytes(data[-2:], "little"):
        raise ProductionError(localized("启动验证", "起動確認"), localized(
            "Modbus响应CRC不匹配", "Modbus応答のCRCが一致しません",
        ))
    if data[:3] != bytes.fromhex("010302") or data[3:5] != bytes.fromhex("0001"):
        raise ProductionError(localized("启动验证", "起動確認"), localized(
            f"设备地址响应不正确：{data.hex().upper()}",
            f"デバイスアドレスの応答が不正です：{data.hex().upper()}",
        ))


def load_manifest(firmware_dir: Path) -> tuple[dict, list[FlashImage]]:
    manifest_path = firmware_dir / "flash-manifest.json"
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise ProductionError(localized("镜像验证", "イメージ検証"), localized(
            f"无法读取发布清单：{exc}", f"リリースマニフェストを読み込めません：{exc}",
        )) from exc
    if manifest.get("version") != VERSION:
        raise ProductionError(localized("镜像验证", "イメージ検証"), localized(
            "烧录工具与固件版本不一致",
            "書き込みツールとファームウェアのバージョンが一致しません",
        ))
    images = [
        FlashImage(
            name=item["file"],
            address=int(item["address"], 0),
            size=int(item["size"]),
            sha256=str(item["sha256"]).lower(),
        )
        for item in manifest.get("images", [])
    ]
    if [item.address for item in images] != [0x0, 0x8000, 0x20000, 0x240000]:
        raise ProductionError(localized("镜像验证", "イメージ検証"), localized(
            "发布清单中的烧录地址不正确",
            "リリースマニフェストの書き込みアドレスが不正です",
        ))
    return manifest, images


def verify_images(firmware_dir: Path) -> list[tuple[int, Path]]:
    _, images = load_manifest(firmware_dir)
    verified: list[tuple[int, Path]] = []
    for image in images:
        path = firmware_dir / image.name
        try:
            payload = path.read_bytes()
        except OSError as exc:
            raise ProductionError(localized("镜像验证", "イメージ検証"), localized(
                f"找不到镜像：{image.name}", f"イメージが見つかりません：{image.name}",
            )) from exc
        digest = hashlib.sha256(payload).hexdigest()
        if len(payload) != image.size or digest != image.sha256:
            raise ProductionError(localized("镜像验证", "イメージ検証"), localized(
                f"镜像校验失败：{image.name}", f"イメージの検証に失敗しました：{image.name}",
            ))
        verified.append((image.address, path))
    return verified


def parse_probe_output(port: str, chip_output: str, flash_output: str) -> DeviceInfo:
    if EXPECTED_CHIP not in chip_output:
        raise ProductionError(localized("芯片检测", "チップ確認"), localized(
            "连接的设备不是ESP32-C3", "接続されたデバイスはESP32-C3ではありません",
        ))
    if "Detected flash size: 4MB" not in flash_output and "Embedded Flash 4MB" not in chip_output:
        raise ProductionError(localized("芯片检测", "チップ確認"), localized(
            "Flash物理容量不是4 MB",
            "フラッシュメモリーの実容量が4 MBではありません",
        ))
    mac = "UNKNOWN"
    for line in chip_output.splitlines():
        if line.strip().startswith("MAC:"):
            mac = line.split(":", 1)[1].strip().upper()
    flash_id = "UNKNOWN"
    manufacturer = ""
    device = ""
    for line in flash_output.splitlines():
        stripped = line.strip()
        if stripped.startswith("Manufacturer:"):
            manufacturer = stripped.split(":", 1)[1].strip()
        elif stripped.startswith("Device:"):
            device = stripped.split(":", 1)[1].strip()
    if manufacturer or device:
        flash_id = f"{manufacturer}:{device}".strip(":")
    return DeviceInfo(port=port, mac=mac, flash_id=flash_id, flash_size=EXPECTED_FLASH)


class EsptoolBackend:
    def __init__(self) -> None:
        self.transcript: list[str] = []
        self.device_info: DeviceInfo | None = None

    def _run(self, arguments: list[str]) -> str:
        output = io.StringIO()
        failure: RuntimeError | None = None
        try:
            with contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
                esptool.main(arguments)
        except SystemExit as exc:
            if exc.code not in (None, 0):
                failure = RuntimeError(output.getvalue().strip() or localized(
                    f"esptool退出码：{exc.code}", f"esptool終了コード：{exc.code}",
                ))
        except Exception as exc:
            failure = RuntimeError(output.getvalue().strip() or str(exc))
        text = output.getvalue()
        self.transcript.append(f"$ esptool {' '.join(arguments)}\n{text}".rstrip())
        if failure is not None:
            raise failure
        return text

    def probe(self, port: str) -> DeviceInfo:
        common = ["--chip", "esp32c3", "--port", port]
        chip_output = self._run(common + ["chip-id"])
        flash_output = self._run(common + ["flash-id"])
        self.device_info = parse_probe_output(port, chip_output, flash_output)
        return self.device_info

    def erase(self, port: str) -> None:
        self._run(["--chip", "esp32c3", "--port", port, "erase-flash"])

    def write(self, port: str, images: list[tuple[int, Path]]) -> None:
        arguments = [
            "--chip", "esp32c3", "--port", port, "--baud", DEFAULT_BAUD,
            "--before", "default-reset", "--after", "hard-reset", "write-flash",
            "--flash-mode", "dio", "--flash-freq", "80m", "--flash-size", "4MB",
        ]
        for address, path in images:
            arguments.extend([hex(address), os.fspath(path)])
        self._run(arguments)

    def verify_application(self, port: str) -> None:
        deadline = time.monotonic() + 12.0
        last_error: Exception | None = None
        while time.monotonic() < deadline:
            try:
                with serial.Serial(port, 115200, timeout=0.35, dsrdtr=False, rtscts=False) as connection:
                    connection.dtr = False
                    connection.rts = False
                    time.sleep(2.8)
                    connection.reset_input_buffer()
                    for _ in range(3):
                        connection.write(MODBUS_REQUEST)
                        connection.flush()
                        response = connection.read(7)
                        if response:
                            validate_modbus_response(response)
                            return
                        time.sleep(0.2)
            except ProductionError:
                raise
            except (OSError, serial.SerialException) as exc:
                last_error = exc
                time.sleep(0.35)
        raise ProductionError(localized("启动验证", "起動確認"), localized(
            f"USB串口Modbus无响应：{last_error or '超时'}",
            f"USBシリアルModbusから応答がありません：{last_error or 'タイムアウト'}",
        ))


def run_production(
    port: str,
    firmware_dir: Path,
    backend: FlashBackend,
    progress: ProgressCallback,
) -> ProductionResult:
    started = time.monotonic()

    def execute(stage: str, percent: int, message: str, operation):
        progress(stage, percent, message)
        try:
            return operation()
        except ProductionError:
            raise
        except Exception as exc:
            raise ProductionError(stage, str(exc)) from exc

    device = execute(localized("芯片检测", "チップ確認"), 10, localized(
        "正在检测芯片、MAC地址和Flash容量",
        "チップ、MACアドレス、フラッシュ容量を確認しています",
    ), lambda: backend.probe(port))
    images = execute(localized("镜像验证", "イメージ検証"), 20, localized(
        "正在验证内置固件的SHA-256",
        "内蔵ファームウェアのSHA-256を検証しています",
    ), lambda: verify_images(firmware_dir))
    execute(localized("整片擦除", "全消去"), 30, localized(
        "正在擦除整个Flash", "フラッシュメモリー全体を消去しています",
    ), lambda: backend.erase(port))
    execute(localized("固件烧录", "ファームウェア書き込み"), 45, localized(
        "正在写入并校验四个镜像",
        "4つのイメージを書き込み、検証しています",
    ), lambda: backend.write(port, images))
    execute(localized("启动验证", "起動確認"), 90, localized(
        "正在等待启动并检查Modbus设备地址",
        "起動を待ち、Modbusデバイスアドレスを確認しています",
    ), lambda: backend.verify_application(port))
    elapsed = time.monotonic() - started
    progress(localized("完成", "完了"), 100, localized(
        f"烧录完成（{elapsed:.1f}秒）",
        f"書き込みが完了しました（{elapsed:.1f}秒）",
    ))
    return ProductionResult(device=device, elapsed_seconds=elapsed)
