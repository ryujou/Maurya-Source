from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import importlib.util
import json
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--variant", choices=("multilingual", "ja"), required=True)
    args = parser.parse_args()
    project = args.project.resolve()
    build = args.build.resolve()
    output = args.output.resolve()
    if output == project or project in output.parents:
        raise SystemExit("release output must be outside the source repository")
    if importlib.util.find_spec("esptool") is None:
        raise SystemExit(
            "esptool is required when packaging the flasher; "
            "install exactly esptool==5.3.0 in the PyInstaller environment"
        )
    installed_esptool = importlib.metadata.version("esptool")
    if installed_esptool != "5.3.0":
        raise SystemExit(
            f"expected esptool 5.3.0, found {installed_esptool}; "
            "use an isolated packaging environment"
        )

    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True, exist_ok=True)
    firmware_output = output / "firmware"
    firmware_output.mkdir()

    image_sources = (
        ("bootloader.bin", 0x0, build / "bootloader/bootloader.bin"),
        ("partition-table.bin", 0x8000, build / "partition_table/partition-table.bin"),
        ("lumia_esp32.bin", 0x20000, build / "lumia_esp32.bin"),
        ("assetsfs.bin", 0x240000, build / "assetsfs.bin"),
    )
    images = []
    for name, address, source in image_sources:
        if not source.is_file():
            raise SystemExit(f"missing build image: {source}")
        target = firmware_output / name
        shutil.copy2(source, target)
        images.append({
            "file": name,
            "address": hex(address),
            "size": target.stat().st_size,
            "sha256": sha256(target),
        })

    manifest = {
        "product": "Maurya",
        "version": args.version,
        "variant": args.variant,
        "gitCommit": args.commit,
        "target": "esp32c3",
        "flashSize": "4MB",
        "esptoolVersion": "5.3.0",
        "baud": 460800,
        "flashMode": "dio",
        "flashFrequency": "80m",
        "eraseBeforeWrite": True,
        "images": images,
    }
    manifest_path = firmware_output / "flash-manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    source_dir = project / "tools" / "production_flasher"
    with tempfile.TemporaryDirectory(prefix="maurya-flasher-") as temp_name:
        temp = Path(temp_name)
        runtime_hook = temp / "release_version.py"
        runtime_hook.write_text(
            "import os\n"
            f"os.environ['MAURYA_FIRMWARE_VERSION'] = {args.version!r}\n"
            f"os.environ['MAURYA_FIRMWARE_VARIANT'] = {args.variant!r}\n",
            encoding="utf-8",
        )
        edition = "JP_" if args.variant == "ja" else ""
        executable_name = f"Maurya_{edition}Flasher_v{args.version}"
        command = [
            sys.executable, "-m", "PyInstaller", "--noconfirm", "--clean",
            "--onefile", "--windowed", "--name", executable_name,
            "--paths", str(project / "tools"),
            "--add-data", f"{firmware_output}{';' if sys.platform == 'win32' else ':'}firmware",
            "--runtime-hook", str(runtime_hook),
            "--distpath", str(temp / "dist"),
            "--workpath", str(temp / "work"),
            "--specpath", str(temp / "spec"),
            "--collect-all", "esptool",
            # esptool's optional interactive/development integrations can make
            # PyInstaller discover unrelated packages from a developer machine.
            # The production GUI uses none of them, and collecting both Qt
            # bindings makes PyInstaller abort the build.
            "--exclude-module", "IPython",
            "--exclude-module", "matplotlib",
            "--exclude-module", "numpy",
            "--exclude-module", "pandas",
            "--exclude-module", "pytest",
            "--exclude-module", "PyQt5",
            "--exclude-module", "PyQt6",
            str(source_dir / "app.py"),
        ]
        subprocess.run(command, check=True)
        executable = temp / "dist" / f"{executable_name}.exe"
        packaged_executable = output / executable.name
        shutil.copy2(executable, packaged_executable)
        subprocess.run(
            [str(packaged_executable), "--smoke-test"],
            check=True,
            timeout=30,
        )

    if args.variant == "ja":
        shutil.copy2(source_dir / "README.ja.md", output / "取扱説明書.md")
    else:
        shutil.copy2(source_dir / "README.zh.md", output / "使用说明.md")
    release_hashes = []
    for path in sorted(
        item
        for item in output.rglob("*")
        if item.is_file()
        and item.suffix.lower() != ".zip"
        and item.name != "SHA256SUMS.txt"
    ):
        release_hashes.append(f"{sha256(path)}  {path.relative_to(output).as_posix()}")
    (output / "SHA256SUMS.txt").write_text("\n".join(release_hashes) + "\n", encoding="utf-8")

    edition = "JP-" if args.variant == "ja" else ""
    archive = output.parent / f"Maurya-{edition}v{args.version}.zip"
    if archive.exists():
        archive.unlink()
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as bundle:
        for path in sorted(item for item in output.rglob("*") if item.is_file()):
            bundle.write(path, Path(output.name) / path.relative_to(output))
    print(f"release: {output}")
    print(f"archive: {archive}")


if __name__ == "__main__":
    main()
