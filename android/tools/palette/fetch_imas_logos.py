from __future__ import annotations

import hashlib
import json
import subprocess
import time
from io import BytesIO
from pathlib import Path
from urllib.parse import quote

import requests
from bs4 import BeautifulSoup
from PIL import Image
from reportlab.graphics import renderPM
from svglib.svglib import svg2rlg


ROOT = Path(__file__).resolve().parent
SOURCE_ROOT = ROOT / "sources" / "imas_logos"
RENDERED_ROOT = SOURCE_ROOT / "rendered"
RETRIEVED_AT = "2026-07-19"
USER_AGENT = "Maurya palette asset builder/3.1 (offline Android asset preparation)"


COMMONS_FILES = {
    "imas_765as": {
        "filename": "765 Production logo.svg",
        "sourcePage": "https://commons.wikimedia.org/wiki/File:765_Production_logo.svg",
    },
    "imas_cinderella": {
        "filename": "THE IDOLM@STER CINDERELLA GIRLS Logo.png",
        "sourcePage": "https://commons.wikimedia.org/wiki/File:THE_IDOLM@STER_CINDERELLA_GIRLS_Logo.png",
    },
    "imas_million": {
        "filename": "THE IDOLM@STER MILLION LIVE! Logo.png",
        "sourcePage": "https://commons.wikimedia.org/wiki/File:THE_IDOLM@STER_MILLION_LIVE!_Logo.png",
    },
    "imas_sidem": {
        "filename": "THE IDOLM@STER SideM Logo.png",
        "sourcePage": "https://commons.wikimedia.org/wiki/File:THE_IDOLM@STER_SideM_Logo.png",
    },
    "imas_gakuen": {
        "filename": "THE IDOLM@STER Gakuen Logo.png",
        "sourcePage": "https://commons.wikimedia.org/wiki/File:THE_IDOLM@STER_Gakuen_Logo.png",
    },
    "imas_other": {
        "filename": "The iDOLM@STER logo.svg",
        "sourcePage": "https://commons.wikimedia.org/wiki/File:The_iDOLM@STER_logo.svg",
    },
}


def sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def fetch(url: str) -> bytes:
    last_error: Exception | None = None
    for attempt in range(3):
        try:
            response = requests.get(url, headers={"User-Agent": USER_AGENT}, timeout=45)
            response.raise_for_status()
            return response.content
        except Exception as exc:
            last_error = exc
            time.sleep(attempt + 1)
    try:
        return subprocess.check_output(
            ["curl.exe", "-L", "--fail", "--silent", "--show-error", "-A", USER_AGENT, url],
        )
    except Exception as exc:
        raise RuntimeError(f"Unable to fetch {url}: {last_error}") from exc


def render_svg(svg_path: Path, output_path: Path, min_width: int = 960) -> None:
    drawing = svg2rlg(str(svg_path))
    if drawing is None:
        raise RuntimeError(f"Unable to render SVG: {svg_path}")
    if drawing.width < min_width:
        scale = min_width / drawing.width
        drawing.scale(scale, scale)
        drawing.width *= scale
        drawing.height *= scale
    renderPM.drawToFile(drawing, str(output_path), fmt="PNG", bg=0x00FFFFFF)


def normalize_png(payload: bytes, output_path: Path) -> None:
    with Image.open(BytesIO(payload)) as image:
        image.convert("RGBA").save(output_path, format="PNG", optimize=True)


def extract_valiv_logo(page_payload: bytes) -> bytes:
    soup = BeautifulSoup(page_payload.decode("utf-8", errors="replace"), "html.parser")
    for heading in soup.find_all("h1"):
        svg = heading.find("svg")
        if svg is None:
            continue
        view_box = svg.get("viewbox") or svg.get("viewBox")
        if view_box == "0 0 137 39":
            svg["xmlns"] = "http://www.w3.org/2000/svg"
            svg["viewBox"] = view_box
            svg.attrs.pop("viewbox", None)
            return str(svg).encode("utf-8")
    raise RuntimeError("Official v-alpha-liv heading logo SVG was not found")


def main() -> None:
    SOURCE_ROOT.mkdir(parents=True, exist_ok=True)
    RENDERED_ROOT.mkdir(parents=True, exist_ok=True)
    manifest: dict[str, object] = {
        "retrievedAt": RETRIEVED_AT,
        "notice": "Official project identification assets. No affiliation or endorsement is implied.",
        "assets": [],
    }

    for group_id, item in COMMONS_FILES.items():
        filename = str(item["filename"])
        download_url = f"https://commons.wikimedia.org/wiki/Special:Redirect/file/{quote(filename)}"
        suffix = Path(filename).suffix.lower()
        source_path = SOURCE_ROOT / f"{group_id}{suffix}"
        payload = source_path.read_bytes() if source_path.exists() else fetch(download_url)
        if not source_path.exists():
            source_path.write_bytes(payload)
        rendered_path = RENDERED_ROOT / f"{group_id}.png"
        if suffix == ".svg":
            render_svg(source_path, rendered_path)
        else:
            normalize_png(payload, rendered_path)
        rendered_payload = rendered_path.read_bytes()
        manifest["assets"].append(
            {
                "id": group_id,
                "sourcePage": item["sourcePage"],
                "downloadUrl": download_url,
                "sourceFile": source_path.name,
                "sourceSha256": sha256(payload),
                "renderedFile": f"rendered/{rendered_path.name}",
                "renderedSha256": sha256(rendered_payload),
                "licenseNote": "Commons file page marks this as PD-textlogo; trademark restrictions may still apply.",
            }
        )

    shiny_url = "https://shinycolors.idolmaster-official.jp/assets/img/common/header_logo.png"
    shiny_source = SOURCE_ROOT / "imas_shiny.png"
    shiny_payload = shiny_source.read_bytes() if shiny_source.exists() else fetch(shiny_url)
    if not shiny_source.exists():
        shiny_source.write_bytes(shiny_payload)
    shiny_rendered = RENDERED_ROOT / "imas_shiny.png"
    normalize_png(shiny_payload, shiny_rendered)
    manifest["assets"].append(
        {
            "id": "imas_shiny",
            "sourcePage": "https://shinycolors.idolmaster-official.jp/",
            "downloadUrl": shiny_url,
            "sourceFile": shiny_source.name,
            "sourceSha256": sha256(shiny_payload),
            "renderedFile": "rendered/imas_shiny.png",
            "renderedSha256": sha256(shiny_rendered.read_bytes()),
            "licenseNote": "Official Bandai Namco project-identification asset; trademark and copyright apply.",
        }
    )

    valiv_page = "https://idolmaster-official.jp/va-liv"
    valiv_source = SOURCE_ROOT / "imas_ds_valiv.svg"
    valiv_svg = valiv_source.read_bytes() if valiv_source.exists() else extract_valiv_logo(fetch(valiv_page))
    if not valiv_source.exists():
        valiv_source.write_bytes(valiv_svg)
    valiv_rendered = RENDERED_ROOT / "imas_ds_valiv.png"
    render_svg(valiv_source, valiv_rendered)
    manifest["assets"].append(
        {
            "id": "imas_ds_valiv",
            "sourcePage": valiv_page,
            "downloadUrl": "inline h1 SVG, viewBox 0 0 137 39",
            "sourceFile": valiv_source.name,
            "sourceSha256": sha256(valiv_svg),
            "renderedFile": "rendered/imas_ds_valiv.png",
            "renderedSha256": sha256(valiv_rendered.read_bytes()),
            "licenseNote": "Official Bandai Namco project-identification asset; trademark and copyright apply.",
        }
    )

    manifest["assets"] = sorted(manifest["assets"], key=lambda item: item["id"])
    (SOURCE_ROOT / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
