# Hardware And Build

## Default GPIO

| Function | Default | Kconfig |
|---|---:|---|
| WS2812 channel 1 | GPIO0 | `CONFIG_LUMIA_LED_CH1_GPIO` |
| WS2812 channel 2 | GPIO1 | `CONFIG_LUMIA_LED_CH2_GPIO` |
| WS2812 channel 3 | GPIO3 | `CONFIG_LUMIA_LED_CH3_GPIO` |
| WS2812 channel 4 | GPIO7 | `CONFIG_LUMIA_LED_CH4_GPIO` |
| WS2812 channel 5 | GPIO10 | `CONFIG_LUMIA_LED_CH5_GPIO` |
| WS2812 channel 6 | GPIO20 | `CONFIG_LUMIA_LED_CH6_GPIO` |
| WS2812 channel 7 | GPIO21 | `CONFIG_LUMIA_LED_CH7_GPIO` |
| BLE status LED | GPIO8 | `CONFIG_LUMIA_BLE_STATUS_LED_GPIO` |
| Spare GPIO | GPIO6 | currently unused |

Default LED counts are `6 + 6 + 6 + 6 + 6 + 6 + 6 = 42`.

## LED Driver Model

- The low-version firmware uses a 7-channel WS2812 scan driver with unified double buffers and per-channel offset mapping.
- GPIO8 is reserved for the on-board BLE status LED and defaults to active-low.
- Effects write a linear RGB frame into the back buffer.
- The TDM driver maps that frame across 7 configured channels and flushes them in channel order.
- Every channel is fixed at 6 LEDs; the firmware enforces the 7 × 6 = 42 geometry at compile time.

## Electrical Requirements

- A 42-pixel WS2812 load can draw up to about 2.52 A at full white (60 mA per pixel), so use a dedicated 5 V supply rated for at least 3 A with additional design margin where practical.
- ESP32-C3 and all LED channels must share ground.
- Use level shifting on WS2812 data lines when needed, and place a 220 to 470 ohm series resistor near each strip input.
- Do not source full LED current from a development board USB 5 V rail.

## Build

```powershell
cd F:\lumia\Lumia_main\lumia_esp32_low\lumia_esp32
idf.py set-target esp32c3
idf.py menuconfig
idf.py build
idf.py -p COMx flash monitor
```

The project uses a custom `partitions.csv`. Reflash the partition table after changing it.

## Verified ESP32-C3 Flash

The production sample with MAC `14:63:93:B3:49:3C` was verified on 2026-07-19
with esptool 5.3.0 as ESP32-C3 revision 0.4 with XMC embedded 4 MB flash. The
previous 2 MB boot message came from the binary image header; esptool reported
the physical flash as 4 MB.

```powershell
$espTool = 'C:\Espressif\tools\python\v6.0.1\venv\Scripts\esptool.exe'
& $espTool --chip esp32c3 --port COMx chip-id
& $espTool --chip esp32c3 --port COMx read-mac
& $espTool --chip esp32c3 --port COMx flash-id
```

The 4 MB layout keeps `lumiacfg` at `0x110000` and `webfs` at `0x114000`.
The factory application moves to `0x160000` and occupies `0x2A0000` bytes.
Do not flash this partition table onto a unit unless `flash-id` reports 4 MB.

## Current Measurement Limits

- `TEMP_C_X100` comes from the ESP32-C3 internal temperature sensor and reports chip temperature, not ambient temperature.
- The current PCB definition does not provide a VDDA divider ADC input, so `VDDA_MV` returns the nominal value `3300 mV`.
- Hardware validation on the real board is still required, especially scan stability and per-channel brightness consistency.
