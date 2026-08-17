# Maurya ESP32 Web UI

Vue 3 + Vite source for the offline ESP32 control page. The firmware does not
need Node.js at runtime. Build and package it with:

```powershell
npm ci
npm run build
npm test
python ..\tools\build_web_assets.py
```

`public/palette.json`, `public/avatars`, and `public/group-icons` are generated,
compact runtime assets and are intentionally tracked so firmware builds do not
depend on the Nichirin repository or the internet.
