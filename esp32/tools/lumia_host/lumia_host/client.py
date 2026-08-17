from __future__ import annotations

import threading
from dataclasses import dataclass

import serial
import serial.tools.list_ports

from .protocol import (
    CONFIG_REG_COUNT,
    DIAG_CLEAR_KEY,
    INNER_MODE_LABELS,
    REG,
    SCENE_MODE_LABELS,
    build_read_holding,
    build_write_multiple,
    build_write_single,
    expected_response_length,
    parse_exception,
    parse_read_holding_response,
    validate_crc,
)


@dataclass
class GroupSnapshot:
    inner_mode: int
    hue: int
    sat: int
    val: int
    inner_param: int

    @property
    def inner_mode_label(self) -> str:
        return INNER_MODE_LABELS.get(self.inner_mode,
                                     f"Inner {self.inner_mode}")


@dataclass
class RuntimeSnapshot:
    scene_mode: int
    scene_param: int
    save_state: int
    device_addr: int
    rx_count: int
    rx_overflow: int
    tx_drop: int
    parse_error: int
    temp_c_x100: int
    vdda_mv: int
    global_brightness: int
    gain_r: int
    gain_g: int
    gain_b: int
    groups: list[GroupSnapshot]

    @property
    def scene_mode_label(self) -> str:
        return SCENE_MODE_LABELS.get(self.scene_mode,
                                     f"Scene {self.scene_mode}")


class LumiaSerialClient:
    def __init__(self) -> None:
        self._serial: serial.Serial | None = None
        self._lock = threading.Lock()

    @staticmethod
    def list_ports() -> list[str]:
        return [port.device for port in serial.tools.list_ports.comports()]

    @property
    def is_connected(self) -> bool:
        return self._serial is not None and self._serial.is_open

    def connect(self, port: str, baudrate: int = 115200) -> None:
        self.disconnect()
        self._serial = serial.Serial(
            port=port,
            baudrate=baudrate,
            timeout=0.2,
            write_timeout=0.5,
        )
        self._serial.reset_input_buffer()
        self._serial.reset_output_buffer()

    def disconnect(self) -> None:
        if self._serial is not None:
            try:
                self._serial.close()
            finally:
                self._serial = None

    def _transceive(self, request: bytes) -> bytes:
        if self._serial is None:
            raise RuntimeError("serial port not connected")

        with self._lock:
            self._serial.reset_input_buffer()
            self._serial.write(request)
            self._serial.flush()

            response = bytearray()
            expected_length: int | None = None
            while True:
                chunk = self._serial.read(64)
                if not chunk:
                    raise TimeoutError("response timeout")
                response.extend(chunk)
                if expected_length is None:
                    expected_length = expected_response_length(response)
                if expected_length is not None and len(response) >= expected_length:
                    frame = bytes(response[:expected_length])
                    if not validate_crc(frame):
                        raise ValueError("CRC mismatch")
                    exception = parse_exception(frame)
                    if exception is not None:
                        raise ValueError(exception)
                    return frame

    def read_snapshot(self, device_addr: int) -> RuntimeSnapshot:
        config_frame = self._transceive(
            build_read_holding(device_addr, 0x0000, CONFIG_REG_COUNT)
        )
        group_frame = self._transceive(
            build_read_holding(
                device_addr,
                REG.GROUP_BASE,
                REG.GROUP_COUNT * REG.GROUP_STRIDE,
            )
        )

        values = parse_read_holding_response(config_frame)
        group_values = parse_read_holding_response(group_frame)
        groups: list[GroupSnapshot] = []
        for group_index in range(REG.GROUP_COUNT):
            base = group_index * REG.GROUP_STRIDE
            groups.append(
                GroupSnapshot(
                    inner_mode=group_values[base],
                    hue=group_values[base + 1],
                    sat=group_values[base + 2],
                    val=group_values[base + 3],
                    inner_param=group_values[base + 4],
                )
            )

        return RuntimeSnapshot(
            scene_mode=values[0],
            scene_param=values[1],
            global_brightness=values[2],
            gain_r=values[3],
            gain_g=values[4],
            gain_b=values[5],
            save_state=values[10],
            device_addr=values[11],
            rx_count=values[12],
            rx_overflow=values[13],
            tx_drop=values[14],
            parse_error=values[15],
            temp_c_x100=self._to_signed_16(values[16]),
            vdda_mv=values[17],
            groups=groups,
        )

    def write_single(self, device_addr: int, reg: int, value: int) -> None:
        self._transceive(build_write_single(device_addr, reg, value))

    def write_multiple(self,
                       device_addr: int,
                       start_reg: int,
                       values: list[int]) -> None:
        self._transceive(build_write_multiple(device_addr, start_reg, values))

    def clear_diag(self, device_addr: int) -> None:
        self.write_single(device_addr, REG.UART_PARSE_ERROR, DIAG_CLEAR_KEY)

    @staticmethod
    def _to_signed_16(value: int) -> int:
        return value - 0x10000 if value & 0x8000 else value
