#!/usr/bin/env python3
"""Validate Maurya's machine-readable wire schema and golden vectors.

This script intentionally uses only the Python standard library so Android,
Swift, firmware, and CI jobs can run the same check without installing a
schema package. It checks both document self-consistency and independently
re-encodes every request vector whose fields are fixed by the current source.
"""

from __future__ import annotations

import json
import gzip
import hashlib
import re
import sys
from pathlib import Path
from typing import Any, Iterable


ROOT = Path(__file__).resolve().parent
REPOSITORY_ROOT = ROOT.parent
SCHEMA_PATH = ROOT / "maurya-protocol.json"
VECTORS_PATH = ROOT / "golden-vectors.json"
UUID_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
)
HEX_RE = re.compile(r"^(?:[0-9a-f]{2})*$")


class Validation:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.check_count = 0

    def check(self, condition: bool, message: str) -> None:
        self.check_count += 1
        if not condition:
            self.errors.append(message)

    def equal(self, actual: Any, expected: Any, message: str) -> None:
        self.check(actual == expected, f"{message}: expected {expected!r}, got {actual!r}")


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError(f"{path.name} must contain a JSON object")
    return value


def decode_hex(value: str, label: str, validation: Validation) -> bytes:
    validation.check(isinstance(value, str), f"{label} must be a string")
    if not isinstance(value, str):
        return b""
    validation.check(bool(HEX_RE.fullmatch(value)), f"{label} must be lowercase, even-length hex")
    try:
        return bytes.fromhex(value)
    except ValueError:
        return b""


def crc16_modbus(data: bytes) -> int:
    crc = 0xFFFF
    for value in data:
        crc ^= value
        for _ in range(8):
            crc = ((crc >> 1) ^ 0xA001) if crc & 1 else (crc >> 1)
    return crc & 0xFFFF


def append_crc(payload: bytes) -> bytes:
    crc = crc16_modbus(payload)
    return payload + bytes((crc & 0xFF, crc >> 8))


def vendor_frame(payload: Iterable[int], address: int = 1) -> bytes:
    body = bytes(payload)
    if len(body) > 239:
        raise ValueError("vendor payload exceeds 239-byte limit")
    return append_crc(bytes((address, 0x41, len(body))) + body)


def u16_be(value: int) -> bytes:
    return value.to_bytes(2, "big", signed=False)


def u16_le(value: int) -> bytes:
    return value.to_bytes(2, "little", signed=False)


def u32_le(value: int) -> bytes:
    return value.to_bytes(4, "little", signed=False)


def modbus_read(address: int, start: int, count: int) -> bytes:
    return append_crc(bytes((address, 0x03)) + u16_be(start) + u16_be(count))


def modbus_write_single(address: int, register: int, value: int) -> bytes:
    return append_crc(bytes((address, 0x06)) + u16_be(register) + u16_be(value))


def modbus_write_multiple(address: int, start: int, values: list[int]) -> bytes:
    encoded = b"".join(u16_be(value) for value in values)
    return append_crc(
        bytes((address, 0x10))
        + u16_be(start)
        + u16_be(len(values))
        + bytes((len(encoded),))
        + encoded
    )


def generated_frames() -> dict[str, bytes]:
    groups = bytearray()
    for index in range(7):
        groups.extend((1,))
        groups.extend(u16_le(index * 50))
        groups.extend((255, 200, 100 + index))

    pixels = bytearray()
    for index in range(42):
        pixels.extend((index, 255 - index, (index * 3) & 0xFF))

    return {
        "modbus-read-groups-first-five": modbus_read(1, 0x0020, 5),
        "modbus-write-global-brightness": modbus_write_single(1, 0x0002, 0x00FF),
        "modbus-write-two-group-registers": modbus_write_multiple(1, 0x0020, [1, 2]),
        "modbus-exception-illegal-value": append_crc(bytes((1, 0x83, 0x03))),
        "vendor-get-info-request": vendor_frame((0x01,)),
        "effect-begin-request": vendor_frame((0x20,)),
        "effect-heartbeat-request": vendor_frame(bytes((0x22,)) + u32_le(0x12345678)),
        "effect-end-request": vendor_frame(bytes((0x23,)) + u32_le(0x12345678)),
        "effect-seven-group-frame": vendor_frame(
            bytes((0x21,)) + u32_le(0x12345678) + u16_le(0x3456) + groups
        ),
        "effect-42-pixel-frame": vendor_frame(
            bytes((0x24,)) + u32_le(0x78563412) + u16_le(0x9ABC) + bytes((1, 42)) + pixels
        ),
        "ota-prepare-request": vendor_frame(bytes((0x02, 0x01, 16)) + bytes(range(16))),
        "ota-ble-begin-request": vendor_frame(
            bytes((0x10,)) + u32_le(987_136) + bytes((2,)) + bytes(32)
        ),
        "ota-ble-data-maximum-android-chunk": vendor_frame(
            bytes((0x11,)) + u32_le(0) + bytes(range(118))
        ),
        "ota-ble-status-request": vendor_frame((0x12,)),
    }


def validate_evidence(schema: dict[str, Any], validation: Validation) -> None:
    evidence_entries: list[str] = []

    def walk(value: Any) -> None:
        if isinstance(value, dict):
            for key, child in value.items():
                if key == "evidence" and isinstance(child, list):
                    evidence_entries.extend(item for item in child if isinstance(item, str))
                else:
                    walk(child)
        elif isinstance(value, list):
            for child in value:
                walk(child)

    walk(schema)
    validation.check(bool(evidence_entries), "schema must contain source evidence")
    for entry in evidence_entries:
        relative_path = entry.split(":", 1)[0]
        validation.check(
            (REPOSITORY_ROOT / relative_path).is_file(),
            f"evidence file does not exist: {relative_path}",
        )


def validate_schema(schema: dict[str, Any], validation: Validation) -> None:
    validation.equal(schema.get("schemaVersion"), "1.0.0", "schema version")

    ble = schema["ble"]
    for key in (
        "serviceUuid",
        "writeCharacteristicUuid",
        "notifyCharacteristicUuid",
        "clientConfigurationDescriptorUuid",
    ):
        value = ble[key]
        validation.check(bool(UUID_RE.fullmatch(value)), f"ble.{key} is not a canonical UUID")
    validation.equal(ble["serviceUuid"][:8], "0000ffe0", "service short UUID")
    validation.equal(ble["writeCharacteristicUuid"][:8], "0000ffe1", "write short UUID")
    validation.equal(ble["notifyCharacteristicUuid"][:8], "0000ffe2", "notify short UUID")

    geometry = schema["geometry"]
    validation.equal(geometry["groupCount"], 7, "group count")
    validation.equal(geometry["pixelsPerGroup"], 6, "pixels per group")
    validation.equal(
        geometry["pixelCount"],
        geometry["groupCount"] * geometry["pixelsPerGroup"],
        "pixel count arithmetic",
    )
    validation.equal(geometry["pixelCount"], 42, "production pixel count")
    validation.equal(geometry["validZeroBasedPixelIndex"]["maximum"], 41, "last pixel index")

    modbus = schema["modbusRtu"]
    validation.equal(modbus["crc"]["initialValueHex"], "ffff", "CRC initial value")
    validation.equal(modbus["crc"]["reflectedPolynomialHex"], "a001", "CRC polynomial")
    validation.equal(modbus["functionCodes"]["vendor"], 0x41, "vendor function")
    validation.equal(
        modbus["vendorEnvelope"]["maximumPayloadBytes"] + 5,
        modbus["vendorEnvelope"]["maximumCompleteFrameBytes"],
        "vendor maximum frame formula",
    )
    validation.equal(
        modbus["vendorEnvelope"]["maximumCompleteFrameBytes"],
        ble["maximumCompleteFrameBytes"],
        "BLE/vendor complete frame budget",
    )

    registers = schema["registerMap"]["groups"]
    validation.equal(registers["count"], geometry["groupCount"], "group register count")
    validation.equal(
        registers["inclusiveEnd"],
        registers["base"] + registers["count"] * registers["stride"] - 1,
        "group register inclusive end",
    )
    validation.equal(registers["exclusiveEnd"], registers["inclusiveEnd"] + 1, "group register exclusive end")
    validation.equal(len(registers["fields"]), registers["stride"], "group register field count")

    capabilities = schema["capabilities"]
    known_masks = [entry["mask"] for entry in capabilities["knownBits"]]
    unknown_masks = capabilities["unknownAdvertisedMasks"]
    validation.equal(known_masks, [0x10, 0x20, 0x40], "known capability masks")
    validation.equal(
        sum(known_masks + unknown_masks),
        capabilities["currentFirmwareAdvertisedValue"],
        "advertised capability mask partition",
    )
    validation.equal(len(set(known_masks + unknown_masks)), len(known_masks + unknown_masks), "unique capability masks")
    for mask in known_masks + unknown_masks:
        validation.check(mask > 0 and mask & (mask - 1) == 0, f"capability mask {mask} is not one bit")

    effects = {entry["name"]: entry for entry in schema["effects"]["commands"]}
    expected_effects = {
        "begin": (0x20, 1, 6),
        "groupFrame": (0x21, 49, 54),
        "heartbeat": (0x22, 5, 10),
        "end": (0x23, 5, 10),
        "pixelFrame": (0x24, 135, 140),
    }
    validation.equal(set(effects), set(expected_effects), "effect command names")
    for name, (code, payload_bytes, frame_bytes) in expected_effects.items():
        command = effects[name]
        validation.equal(command["code"], code, f"{name} command code")
        validation.equal(command["requestPayloadBytes"], payload_bytes, f"{name} payload length")
        validation.equal(command["requestCompleteFrameBytes"], frame_bytes, f"{name} frame length")
        validation.equal(frame_bytes, payload_bytes + 5, f"{name} vendor envelope length")
    validation.equal(
        effects["pixelFrame"]["requestPayloadBytes"],
        1 + 4 + 2 + 1 + 1 + geometry["pixelCount"] * 3,
        "42-pixel payload formula",
    )
    validation.equal(effects["pixelFrame"]["requestCompleteFrameBytes"], 140, "42-pixel frame length")
    validation.equal(schema["effects"]["timingMilliseconds"]["firmwareSessionTimeout"], 5000, "effect session timeout")

    ota = schema["ota"]
    validation.equal(ota["maximumBleDataChunkBytes"], 118, "OTA BLE data chunk")
    ota_commands = {entry["name"]: entry for entry in ota["commands"]}
    expected_ota_codes = {
        "getInfo": 0x01,
        "prepareWifi": 0x02,
        "cancelPrepare": 0x03,
        "bleBegin": 0x10,
        "bleData": 0x11,
        "bleStatus": 0x12,
        "bleCommit": 0x14,
        "bleCancel": 0x15,
    }
    validation.equal(
        {name: entry["code"] for name, entry in ota_commands.items()},
        expected_ota_codes,
        "OTA command map",
    )
    ble_data = ota_commands["bleData"]
    validation.equal(ble_data["requestPayloadBytes"]["maximum"], 1 + 4 + 118, "OTA max payload")
    validation.equal(ble_data["requestCompleteFrameBytes"]["maximum"], 128, "OTA max frame")
    validation.check(
        ble_data["requestCompleteFrameBytes"]["maximum"] <= ble["maximumCompleteFrameBytes"],
        "OTA max frame exceeds BLE transport capacity",
    )
    validation.equal([entry["value"] for entry in ota["states"]], list(range(6)), "OTA state values")

    unresolved_ids = [entry["id"] for entry in schema["unresolved"]]
    validation.equal(len(unresolved_ids), len(set(unresolved_ids)), "unique unresolved IDs")
    validate_evidence(schema, validation)


def validate_vectors(
    schema: dict[str, Any], vectors: dict[str, Any], validation: Validation
) -> None:
    validation.equal(vectors.get("vectorVersion"), "1.1.0", "vector version")
    validation.equal(vectors.get("schemaFile"), SCHEMA_PATH.name, "vector schema filename")
    validation.equal(vectors.get("sourceCommit"), schema.get("sourceCommit"), "source commit agreement")

    crc_vectors = {entry["id"]: entry for entry in vectors["crc"]}
    validation.equal(set(crc_vectors), {"crc-empty", "crc-ascii-123456789"}, "CRC vector IDs")
    for vector in crc_vectors.values():
        data = decode_hex(vector["inputHex"], f"{vector['id']}.inputHex", validation)
        actual = crc16_modbus(data)
        validation.equal(f"{actual:04x}", vector["crcValueHex"], f"{vector['id']} CRC value")
        suffix = bytes((actual & 0xFF, actual >> 8)).hex()
        validation.equal(suffix, vector["wireSuffixHex"], f"{vector['id']} CRC wire suffix")

    frame_vectors = {entry["id"]: entry for entry in vectors["frames"]}
    generated = generated_frames()
    validation.equal(set(frame_vectors), set(generated), "generated/golden frame IDs")
    for vector_id, vector in frame_vectors.items():
        frame = decode_hex(vector["hex"], f"{vector_id}.hex", validation)
        validation.equal(len(frame), vector["completeFrameBytes"], f"{vector_id} declared length")
        validation.check(len(frame) >= 4, f"{vector_id} is too short for Modbus RTU")
        if len(frame) >= 4:
            crc = crc16_modbus(frame[:-2])
            actual_suffix = int.from_bytes(frame[-2:], "little")
            validation.equal(actual_suffix, crc, f"{vector_id} CRC suffix")
            validation.equal(f"{crc:04x}", vector["expectedCrcValueHex"], f"{vector_id} CRC value")
        validation.equal(frame, generated[vector_id], f"{vector_id} independent encoding")
        if len(frame) >= 5 and frame[1] == 0x41:
            validation.equal(frame[2], len(frame) - 5, f"{vector_id} vendor payload header")
            validation.equal(frame[2], vector["vendorPayloadBytes"], f"{vector_id} vendor payload declaration")

    pixel_frame = decode_hex(frame_vectors["effect-42-pixel-frame"]["hex"], "pixel frame", validation)
    validation.equal(len(pixel_frame), 140, "golden pixel complete frame")
    validation.equal(pixel_frame[2], 135, "golden pixel vendor payload")
    validation.equal(pixel_frame[3], 0x24, "golden pixel command")
    validation.equal(pixel_frame[10], 1, "golden pixel format")
    validation.equal(pixel_frame[11], schema["geometry"]["pixelCount"], "golden pixel count")
    validation.equal(pixel_frame[12:15], bytes((0, 255, 0)), "golden first pixel")
    validation.equal(pixel_frame[-5:-2], bytes((41, 214, 123)), "golden final pixel")

    mapping = vectors["mapping"]
    validation.equal(len(mapping), 5, "mapping boundary vector count")
    for entry in mapping:
        calculated = (
            (entry["groupOneBased"] - 1) * schema["geometry"]["pixelsPerGroup"]
            + entry["pixelInGroupOneBased"]
            - 1
        )
        validation.equal(calculated, entry["linearZeroBased"], f"mapping {entry}")
        validation.equal(calculated + 1, entry["globalOneBased"], f"global mapping {entry}")
    validation.equal(mapping[-1]["globalOneBased"], 42, "last global pixel")
    validation.equal(mapping[-1]["linearZeroBased"], 41, "last zero-based pixel")

    share_vectors = vectors["shareEnvelopes"]
    validation.check(bool(share_vectors), "at least one shared share envelope vector")
    for vector in share_vectors:
        vector_id = vector["id"]
        payload = {
            "editorSchema": vector["editorSchema"],
            "programSchema": vector["programSchema"],
            "source": vector["source"],
            "sourceKind": vector["sourceKind"],
        }
        names = vector["displayName"]
        canonical_payload = json.dumps(
            payload, ensure_ascii=False, separators=(",", ":"), sort_keys=True
        )
        digest = hashlib.sha256(b"maurya-share-v1\0")
        for component in (vector["kind"], names["zh"], names["ja"], canonical_payload):
            encoded = component.encode("utf-8")
            digest.update(len(encoded).to_bytes(4, "big"))
            digest.update(encoded)
        validation.equal(digest.hexdigest(), vector["contentHash"], f"{vector_id} content hash")

        envelope = {
            "contentHash": vector["contentHash"],
            "displayName": {"ja": names["ja"], "zh": names["zh"]},
            "kind": vector["kind"],
            "payload": payload,
            "schema": 1,
        }
        request_canonical = json.dumps(
            envelope, ensure_ascii=False, separators=(",", ":"), sort_keys=True
        )
        validation.equal(
            request_canonical,
            vector["requestCanonicalUtf8"],
            f"{vector_id} request canonical JSON",
        )
        envelope["createdAt"] = vector["createdAt"]
        server_canonical = json.dumps(
            envelope, ensure_ascii=False, separators=(",", ":"), sort_keys=True
        )
        validation.equal(
            server_canonical,
            vector["serverCanonicalUtf8"],
            f"{vector_id} server canonical JSON",
        )
        compressed = decode_hex(vector["serverGzipHex"], f"{vector_id}.serverGzipHex", validation)
        validation.equal(
            hashlib.sha256(compressed).hexdigest(),
            vector["serverBlobSha256"],
            f"{vector_id} gzip SHA-256",
        )
        try:
            expanded = gzip.decompress(compressed).decode("utf-8")
        except (gzip.BadGzipFile, UnicodeDecodeError, EOFError) as error:
            validation.check(False, f"{vector_id} invalid gzip/UTF-8: {error}")
        else:
            validation.equal(expanded, server_canonical, f"{vector_id} gzip content")


def main() -> int:
    validation = Validation()
    try:
        schema = load_json(SCHEMA_PATH)
        vectors = load_json(VECTORS_PATH)
        validate_schema(schema, validation)
        validate_vectors(schema, vectors, validation)
    except (KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
        validation.errors.append(f"validation aborted: {error}")

    if validation.errors:
        print(f"Maurya protocol validation FAILED ({len(validation.errors)} errors)", file=sys.stderr)
        for error in validation.errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print(
        "Maurya protocol validation passed: "
        f"{validation.check_count} checks, "
        f"{len(vectors['frames'])} frame vectors, "
        f"geometry {schema['geometry']['groupCount']}x"
        f"{schema['geometry']['pixelsPerGroup']}="
        f"{schema['geometry']['pixelCount']}, pixel frame 140 bytes"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
