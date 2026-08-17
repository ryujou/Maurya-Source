# Maurya 通信协议

本目录是 Android、iOS、ESP32 固件和工具共同使用的机器可读协议基线。文件内容以当前源码和黄金向量为准，不在各端复制一份容易漂移的常量。

## 文件

- maurya-protocol.json：传输方式、42 颗灯的几何、Modbus 寄存器、能力位、灯效和 OTA 字段。
- golden-vectors.json：CRC、Modbus、厂商灯效/OTA 帧、几何、分享规范 JSON、哈希和 gzip 的字节级样例。
- fixtures/effect-algorithms.json：Android 与 Swift 灯效数学和图案算法的共同测试数据。
- validate_protocol.py：只依赖 Python 标准库的结构、范围和黄金编码校验。

在仓库根目录运行：

~~~
python protocol/validate_protocol.py
~~~

## 当前线格式

1. 设备逻辑几何固定为 7 组 × 6 颗 = 42 颗，索引按组优先排列，零基索引为 0...41。
2. Modbus 地址、寄存器、数量和值使用大端；CRC 两个字节按低字节在前发送。厂商灯效和 OTA 负载中的多字节字段按协议文件定义的小端排列。
3. 厂商帧结构为“地址、0x41、负载长度、负载、CRC低字节、CRC高字节”。
4. 42 颗灯的 RGB888 帧在当前协议下为 140 字节（包含 Modbus 外层和 CRC）。
5. BLE 默认使用 FFE0 服务、FFE1 写入和 FFE2 通知；USB Serial Modbus 与 Wi-Fi 控制复用相同的寄存器/帧语义。
6. 能力位中未定义的 bit 必须保留但不能擅自解释；unresolved 中的项目必须先有双方代码证据和变更记录才能落地。

## 跨端使用规则

- 客户端应直接读取 JSON 或从 JSON 生成常量，并用本端测试对照 golden-vectors.json。
- 修改字段、字节顺序、几何或能力位时，必须同步 Android、iOS、ESP32 和测试向量；不要只改某一端。
- 解析器要拒绝长度、CRC、类型、边界或未知关键字段不符合约束的输入。
- 分享信封的规范 JSON、内容 SHA-256、gzip 和头像 WebP 限制同样属于协议的一部分，Android/iOS 测试必须保持一致。
