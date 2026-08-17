# Lumia Host Tool

Python host utility for the ESP32-C3 USB serial port. It talks Modbus RTU
directly over the built-in USB serial transport.

## Install

```bash
python -m pip install -r tools/lumia_host/requirements.txt
```

## Run

```bash
python tools/lumia_host/app.py
```

## Features

- Connect to the ESP32 USB serial port
- Read and write the new dual-layer runtime registers
- Configure global scene mode and scene speed
- Configure per-group inner mode, hue, saturation, value, and inner param
- Adjust global brightness and RGB white balance
- Read telemetry and clear diagnostics
- Copy Group 1 settings to all groups or apply one group to every group
