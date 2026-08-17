# ESP32-C3 一键烧录工具源码

本目录是 Windows Tk 界面和烧录核心的 Python 源码。它只接受一块目标板，调用 esptool 擦除整片 Flash、写入清单中的镜像，再通过 USB Serial Modbus 检查设备地址和应用是否正常响应。发布 EXE 的构建脚本是 build_release.py；本仓库不包含 EXE、BIN 或发布压缩包。

## 源码运行

~~~
cd esp32/lumia_esp32/tools
python -m production_flasher.app
~~~

运行需要 esptool、pyserial 和 Tk。生产构建会把固定镜像、版本、Flash 参数和 SHA-256 写入 flash-manifest.json，烧录前后都会检查芯片为 ESP32-C3、Flash 为 4 MB、镜像哈希和写入校验；任何一项失败都不会报告成功。

## 使用注意

- 只连接一块控制板，烧录会整片擦除，原有配置不能恢复。
- 日志写入程序目录的 logs；没有写权限时回退到 %LOCALAPPDATA%\MauryaFlasher\logs。
- 具体的中文/日文界面文案分别见 README.zh.md 和 README.ja.md。发布版本、镜像和签名应由发布目录提供，不能在源码仓库中手工替换。
