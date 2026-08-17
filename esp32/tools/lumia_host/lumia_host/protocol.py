from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence


def crc16_modbus(data: bytes) -> int:
    crc = 0xFFFF
    for byte in data:
        crc ^= byte
        for _ in range(8):
            if crc & 1:
                crc = (crc >> 1) ^ 0xA001
            else:
                crc >>= 1
    return crc & 0xFFFF


def append_crc(payload: bytes) -> bytes:
    crc = crc16_modbus(payload)
    return payload + bytes((crc & 0xFF, (crc >> 8) & 0xFF))


def validate_crc(frame: bytes) -> bool:
    if len(frame) < 4:
        return False
    expected = crc16_modbus(frame[:-2])
    actual = frame[-2] | (frame[-1] << 8)
    return expected == actual


def expected_response_length(buffer: bytes) -> int | None:
    if len(buffer) < 2:
        return None
    function = buffer[1]
    if function == 0x03:
        if len(buffer) < 3:
            return None
        return 5 + buffer[2]
    if function in (0x06, 0x10):
        return 8
    if function & 0x80:
        return 5
    raise ValueError(f"unsupported function 0x{function:02X}")


@dataclass(frozen=True)
class Registers:
    SCENE_MODE: int = 0x0000
    SCENE_PARAM: int = 0x0001
    LED_GLOBAL_BRI: int = 0x0002
    LED_GAIN_R: int = 0x0003
    LED_GAIN_G: int = 0x0004
    LED_GAIN_B: int = 0x0005
    CFG_SAVE_STATE: int = 0x000A
    DEVICE_ADDR: int = 0x000B
    UART_RX_COUNT: int = 0x000C
    UART_RX_OVERFLOW: int = 0x000D
    UART_TX_DROP: int = 0x000E
    UART_PARSE_ERROR: int = 0x000F
    TEMP_C_X100: int = 0x0010
    VDDA_MV: int = 0x0011
    GROUP_BASE: int = 0x0020
    GROUP_STRIDE: int = 0x0005
    GROUP_COUNT: int = 7


REG = Registers()
DIAG_CLEAR_KEY = 0xA55A
CONFIG_REG_COUNT = 22

SCENE_MODE_LABELS = {
    1: "Static",
    2: "Chase L->R",
    3: "Chase R->L",
    4: "PingPong",
}

INNER_MODE_LABELS = {
    1: "Steady",
    2: "Breath",
    3: "Strobe",
    4: "Fade",
}


def build_read_holding(device_addr: int, start_reg: int, count: int) -> bytes:
    payload = bytes(
        (
            device_addr,
            0x03,
            (start_reg >> 8) & 0xFF,
            start_reg & 0xFF,
            (count >> 8) & 0xFF,
            count & 0xFF,
        )
    )
    return append_crc(payload)


def build_write_single(device_addr: int, reg: int, value: int) -> bytes:
    payload = bytes(
        (
            device_addr,
            0x06,
            (reg >> 8) & 0xFF,
            reg & 0xFF,
            (value >> 8) & 0xFF,
            value & 0xFF,
        )
    )
    return append_crc(payload)


def build_write_multiple(device_addr: int,
                         start_reg: int,
                         values: Sequence[int]) -> bytes:
    if not values:
        raise ValueError("values must not be empty")
    count = len(values)
    body = bytearray(
        (
            device_addr,
            0x10,
            (start_reg >> 8) & 0xFF,
            start_reg & 0xFF,
            (count >> 8) & 0xFF,
            count & 0xFF,
            count * 2,
        )
    )
    for value in values:
        body.extend(((value >> 8) & 0xFF, value & 0xFF))
    return append_crc(bytes(body))


def parse_read_holding_response(frame: bytes) -> list[int]:
    if len(frame) < 5 or frame[1] != 0x03:
        raise ValueError("not a read holding response")
    byte_count = frame[2]
    if len(frame) != byte_count + 5:
        raise ValueError("length mismatch")
    values: list[int] = []
    for offset in range(3, 3 + byte_count, 2):
        values.append((frame[offset] << 8) | frame[offset + 1])
    return values


def parse_exception(frame: bytes) -> str | None:
    if len(frame) == 5 and (frame[1] & 0x80):
        code = frame[2]
        return {
            0x02: "Illegal address",
            0x03: "Illegal value",
        }.get(code, f"Modbus exception 0x{code:02X}")
    return None
