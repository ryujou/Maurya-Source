# Lumia ESP32-C3 Low

Lumia ESP32-C3 low-version firmware. The ESP-IDF project root is `lumia_esp32/`.

Implemented:

- NimBLE GATT: `FFE0` service, `FFE1` write, `FFE2` notify
- Modbus function codes: `0x03 / 0x06 / 0x10`
- Register ranges `0x0000..0x0015` and `0x0020..0x0042`
- Dual-layer effects:
  - Global scenes: Static, Chase L->R, Chase R->L, PingPong
  - Per-group inner modes: Steady, Breath, Strobe, Fade
- 7-channel WS2812 scan driver with configurable per-channel LED counts
- Internal Flash dual-slot configuration persistence
- Chip temperature and transport diagnostics
- GPIO9 scene mode button and GPIO4 deep-sleep wake control

## Build

```powershell
cd F:\lumia\Lumia_main\lumia_esp32_low\lumia_esp32
idf.py set-target esp32c3
idf.py build
idf.py -p COMx flash monitor
```

Hardware wiring and build notes are in [HARDWARE_AND_BUILD.md](docs/HARDWARE_AND_BUILD.md).
BLE name is configured by `CONFIG_LUMIA_BLE_DEVICE_NAME` under `Component config -> Lumia platform configuration`.

- [BLE_PROTOCOL_NOTES.md](docs/BLE_PROTOCOL_NOTES.md)
- [REGISTER_COMPATIBILITY_MATRIX.md](docs/REGISTER_COMPATIBILITY_MATRIX.md)
- [FLASH_STORAGE_LAYOUT.md](docs/FLASH_STORAGE_LAYOUT.md)
