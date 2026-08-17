# USB Serial Modbus 主机工具

这是面向 ESP32-C3 内置 USB 串口的 Python 工具，直接使用 Modbus RTU 读写设备寄存器，不经过 BLE 或 Wi-Fi。

## 安装与运行

~~~
cd esp32/tools/lumia_host
python -m pip install -r requirements.txt
python app.py
~~~

工具可以连接串口、读取/写入运行时寄存器、配置全局场景和速度、设置每组模式/HSV/参数、修改全局亮度与 RGB 白平衡、读取遥测和清除诊断；还可以把第 1 组配置复制到全部组，或把某一组应用到其他组。实际可写范围仍受 protocol/maurya-protocol.json 和固件寄存器映射限制。
