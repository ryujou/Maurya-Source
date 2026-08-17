from __future__ import annotations

import json
import re
import subprocess
import time
import urllib.parse
import urllib.request
from urllib.error import HTTPError
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / "sources" / "imas-logos"
COMMONS_API = "https://commons.wikimedia.org/w/api.php"
USER_AGENT = "MauryaESP32Prototype/0.1 (local asset preparation)"

COMMONS_FILES = {
    "imas_765as": "File:765 Production logo.svg",
    "imas_cinderella": "File:THE IDOLM@STER CINDERELLA GIRLS Logo.png",
    "imas_million": "File:THE IDOLM@STER MILLION LIVE! Logo.png",
    "imas_sidem": "File:THE IDOLM@STER SideM Logo.png",
    "imas_gakuen": "File:THE IDOLM@STER Gakuen Logo.png",
    "imas_other": "File:THE IDOLM@STER Logo (2010-2016).png",
}

OFFICIAL_FILES = {
    "imas_shiny": "https://shinycolors.idolmaster-official.jp/assets/img/top/kv_logo.png",
}
EDGE = Path(r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe")


def request_bytes(url: str) -> bytes:
    for attempt in range(5):
        request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                content = response.read()
            time.sleep(1)
            return content
        except Exception as error:
            if isinstance(error, HTTPError) and error.code != 429:
                raise
            if attempt == 4:
                raise
            time.sleep(3 * (attempt + 1))
    raise RuntimeError(f"failed to fetch {url}")


def commons_image(title: str) -> tuple[str, bytes]:
    query = urllib.parse.urlencode({
        "action": "query",
        "format": "json",
        "prop": "imageinfo",
        "iiprop": "url",
        "iiurlwidth": "640",
        "titles": title,
    })
    payload = json.loads(request_bytes(f"{COMMONS_API}?{query}"))
    page = next(iter(payload["query"]["pages"].values()))
    info = page["imageinfo"][0]
    url = info.get("thumburl") or info["url"]
    return url, request_bytes(url)


def fetch_valiv_logo() -> tuple[str, tuple[int, int]]:
    page_url = "https://idolmaster-official.jp/va-liv/"
    html = request_bytes(page_url).decode("utf-8")
    match = re.search(r'(<svg[^>]+viewBox="0 0 137 39".*?</svg>)', html, re.DOTALL)
    if not match:
        raise RuntimeError("vα-liv inline logo was not found")
    wrapper = TARGET / "valiv-logo-render.html"
    wrapper.write_text(
        '<!doctype html><style>html,body{margin:0;width:640px;height:200px;background:transparent;display:grid;place-items:center}svg{width:600px;height:auto}</style>' + match.group(1),
        encoding="utf-8",
    )
    destination = TARGET / "imas_ds_valiv.png"
    result = subprocess.run([
        str(EDGE), "--headless=new", "--disable-gpu", "--hide-scrollbars",
        "--default-background-color=00000000", "--window-size=640,200",
        f"--screenshot={destination}", wrapper.resolve().as_uri(),
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    wrapper.unlink(missing_ok=True)
    if result.returncode != 0 or not destination.exists():
        raise RuntimeError("failed to render official vα-liv SVG")
    with Image.open(destination) as image:
        return page_url, image.size


def main() -> None:
    TARGET.mkdir(parents=True, exist_ok=True)
    manifest_path = TARGET / "sources.json"
    previous = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.exists() else []
    previous_by_id = {item["groupId"]: item for item in previous}
    manifest = []
    for group_id, title in COMMONS_FILES.items():
        source_page = f"https://commons.wikimedia.org/wiki/{urllib.parse.quote(title.replace(' ', '_'))}"
        destination = TARGET / f"{group_id}.png"
        cached = previous_by_id.get(group_id)
        if destination.exists() and cached and cached.get("sourcePage") == source_page:
            manifest.append(cached)
            continue
        url, content = commons_image(title)
        destination.write_bytes(content)
        with Image.open(destination) as image:
            size = image.size
        manifest.append({"groupId": group_id, "source": url, "sourcePage": source_page, "size": size})

    for group_id, url in OFFICIAL_FILES.items():
        destination = TARGET / f"{group_id}.png"
        cached = previous_by_id.get(group_id)
        if destination.exists() and cached and cached.get("source") == url:
            manifest.append(cached)
            continue
        destination.write_bytes(request_bytes(url))
        with Image.open(destination) as image:
            size = image.size
        manifest.append({"groupId": group_id, "source": url, "sourcePage": url.rsplit("/assets/", 1)[0] + "/", "size": size})

    cached_valiv = previous_by_id.get("imas_ds_valiv")
    if cached_valiv and cached_valiv.get("sourcePage") == "https://idolmaster-official.jp/va-liv/" and (TARGET / "imas_ds_valiv.png").exists():
        manifest.append(cached_valiv)
    else:
        valiv_source, valiv_size = fetch_valiv_logo()
        manifest.append({"groupId": "imas_ds_valiv", "source": "inline official SVG", "sourcePage": valiv_source, "size": valiv_size})

    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
