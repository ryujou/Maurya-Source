from __future__ import annotations

import gzip
import shutil
from pathlib import Path


GZIP_SUFFIXES = {".html", ".css", ".js", ".json", ".svg"}


def main() -> None:
    project = Path(__file__).resolve().parents[1]
    source = (project / "web_ui" / "dist").resolve()
    output = (project / "web").resolve()
    if source.parent != (project / "web_ui").resolve() or not source.is_dir():
        raise SystemExit("web_ui/dist is missing; run npm run build first")
    if output.parent != project.resolve() or output.name != "web":
        raise SystemExit(f"refusing unsafe output path: {output}")

    if output.exists():
        shutil.rmtree(output)
    output.mkdir()

    stored_bytes = 0
    file_count = 0
    for item in sorted(source.rglob("*")):
        if not item.is_file():
            continue
        relative = item.relative_to(source)
        target = output / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        data = item.read_bytes()
        if item.suffix.lower() in GZIP_SUFFIXES:
            target = target.with_name(target.name + ".gz")
            data = gzip.compress(data, compresslevel=9, mtime=0)
        target.write_bytes(data)
        stored_bytes += len(data)
        file_count += 1

    avatars = len(list((output / "avatars").glob("*.webp")))
    icons = len(list((output / "group-icons").glob("*.webp")))
    if avatars != 505 or icons != 31:
        raise SystemExit(f"asset count mismatch: avatars={avatars}, icons={icons}")
    print(f"web assets: files={file_count}, stored={stored_bytes} bytes")


if __name__ == "__main__":
    main()
