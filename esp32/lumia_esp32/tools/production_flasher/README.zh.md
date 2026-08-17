# Maurya v1.8.2 BLE OTA一键烧录工具

## 操作步骤

1. 只连接一块Maurya ESP32-C3控制板。
2. 双击`Maurya_Flasher_v1.8.2.exe`。
3. 确认界面只显示一个串口，然后点击“一键烧录”。
4. 确认整片擦除，等待界面显示“烧录成功”。
5. 拔下控制板，再连接下一块。

本工具会整片擦除旧布局并写入支持双槽及APP蓝牙OTA的新布局，现有无线模式和灯效配置会恢复默认。完成这一次USB迁移后，后续固件可直接通过Maurya APP的BLE连接更新，无需切换Wi-Fi。

烧录成功必须同时满足：芯片为ESP32-C3、Flash物理容量为4 MB、四个镜像的SHA-256与写入校验正确，以及重启后USB Serial Modbus设备地址为1。

## 默认设置

- BLE设备名：`Maurya-XXXX`，后缀来自设备MAC。
- Wi-Fi热点：`Maurya-XXXX`，与BLE使用同一后缀。
- Wi-Fi密码：`Maurya123`
- GPIO4开关处于OFF时，设备启动后会熄灯并进入深睡眠。

## 注意事项

- 烧录会整片擦除，原有设置无法恢复。
- 每次只能连接一块控制板。
- 不需要安装Python、ESP-IDF，也不需要联网。
- EXE没有商业代码签名，Windows SmartScreen可能显示警告。
- 日志默认保存在EXE旁边的`logs`目录；无写入权限时保存到`%LOCALAPPDATA%\MauryaFlasher\logs`。

## 故障排查

- “未找到设备”：检查USB数据线、驱动和控制板电源，再点击“刷新设备”。
- “检测到多个设备”：断开其他ESP32，只保留一块控制板。
- “Flash物理容量不是4 MB”：该控制板不适用于本固件，不要继续烧录。
- “USB串口Modbus无响应”：重新插拔控制板后重试，仍失败时保留日志。
- 任何步骤报错的控制板都不应按合格品出货。

## 开发者构建信息

单文件程序使用esptool 5.3.0和PyInstaller生成。`build_release.py`会把固定镜像、清单和SHA-256内置到EXE中，发布后请勿手工替换BIN文件。
