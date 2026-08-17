# Lumia ESP32-C3 Firmware

ESP-IDF v6.0.1 project targeting ESP32-C3.

```powershell
idf.py build
idf.py -p COMx flash monitor
```

Configuration is available under `Component config -> Lumia platform configuration`.

The firmware is event driven: NimBLE callbacks only enqueue complete requests or diagnostic events; `app_task` is the sole owner of runtime state, effect scheduling, persistence state, sensor services, and LED refresh.

See the parent [README](../README.md), [hardware guide](../docs/HARDWARE_AND_BUILD.md),
and [standard firmware release process](../docs/FIRMWARE_RELEASE_PROCESS.md).
