# THE IDOLM@STER project logos

These files are used only to identify projects in the unofficial Maurya support-light controller. Their inclusion does not imply affiliation with or endorsement by Bandai Namco Entertainment.

`manifest.json` is the source of truth for each original URL, retrieval date, source SHA-256, generated PNG SHA-256, and license/trademark note. Run the following commands from the repository root to reproduce the 320 x 160 transparent derivatives used by the Android app:

```powershell
python tools/palette/fetch_imas_logos.py
python tools/palette/crawl_imas.py
python tools/palette/build_catalog.py
```

The Wikimedia Commons file pages identify the selected simple wordmarks as `PD-textlogo`; trademark restrictions may still apply. The Shiny Colors and vα-liv assets come from their official project pages and remain copyrighted/trademarked by their respective owners.

No logo is recolored, stretched, or cropped. The pipeline only scales each source proportionally and centers it with transparent padding.
