from __future__ import annotations

import argparse
import base64
import hashlib
import json
import shutil
from datetime import datetime, timezone
from pathlib import Path

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description="Build signed Maurya OTA server artifacts")
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--build", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--variant", choices=("multilingual", "ja"), required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--secure-version", type=int, required=True)
    parser.add_argument("--private-key", type=Path, required=True)
    parser.add_argument("--base-url", default="https://xtbang.top/maurya/ota/stable")
    args = parser.parse_args()

    project = args.project.resolve()
    build = (args.build or project / "build_ota").resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    image = build / "lumia_esp32.bin"
    if not image.is_file():
        raise SystemExit(f"missing signed application: {image}")
    target = output / f"maurya-{args.version}.bin"
    shutil.copy2(image, target)

    manifest = {
        "schema": 1,
        "variant": args.variant,
        "layoutVersion": 2,
        "assetPackVersion": 1,
        "versionName": args.version,
        "monotonicVersion": args.secure_version,
        "secureVersion": args.secure_version,
        "size": target.stat().st_size,
        "sha256": sha256(target),
        "downloadUrl": f"{args.base_url}/{args.variant}/{target.name}",
        "minimumAppVersion": 313,
        "publishedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "releaseNotesZh": "新增Wi-Fi启动自动信道：扫描后从1/6/11中选择干扰最低的信道；保持7组×6颗（42颗）、Wi-Fi 8.5 dBm与BLE 6 dBm。",
        "releaseNotesJa": "Wi-Fi起動時に周辺をスキャンし、1/6/11から干渉の少ないチャンネルを自動選択します。LEDは7×6（42個）、Wi-Fi 8.5 dBm、BLE 6 dBmです。",
    }
    encoded = (json.dumps(
        manifest, ensure_ascii=False, separators=(",", ":"), sort_keys=True,
    ) + "\n").encode("utf-8")
    (output / "manifest.json").write_bytes(encoded)

    private_key = serialization.load_pem_private_key(
        args.private_key.read_bytes(), password=None,
    )
    signature = private_key.sign(encoded, padding.PKCS1v15(), hashes.SHA256())
    (output / "manifest.sig").write_text(
        base64.b64encode(signature).decode("ascii") + "\n", encoding="ascii",
    )
    (output / f"{target.name}.sha256").write_text(
        f"{manifest['sha256']}  {target.name}\n", encoding="ascii",
    )
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
