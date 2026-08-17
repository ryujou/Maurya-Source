# MauryaOTA 蓝牙升级

MauryaOTA 是 iOS 17 OTA 的安全校验和传输边界，依赖 MauryaProtocol、MauryaDevice、MauryaBluetooth；网络、BLE、签名公钥和断点存储都通过协议注入，便于测试。

## 实现内容

- 只从明确允许的 HTTPS 主机获取清单和镜像，使用 Security.framework 验证版本化 RSA PKCS#1 v1.5 SHA-256 签名。
- 清单校验 schema、应用版本、变体、布局、资源包、BLE 能力、安全版本、大小、URL 和 SHA-256；任何失败都在发送固件前停止。
- 通过 actor 驱动 BLE_BEGIN、BLE_DATA、BLE_STATUS、BLE_COMMIT、BLE_CANCEL；分片大小为 min(118, 适配器写入能力)，确认、重试、重连和取消均有界。
- 断点恢复必须同时匹配设备身份、目标版本、安全版本、镜像大小/哈希、ETag、实时设备状态、期望字节数和偏移；不一致时安全地从零开始。
- JSON checkpoint store 原子写入，区分已验证、提交结果未知和提交已确认；只有重连后 GET_INFO 读到目标版本才报告成功。
- URLSessionOTAClient 支持无备份缓存、磁盘空间检查、Range/If-Range/ETag、HTTP 200/416 和校验器变化时的安全重启。

PREPARE 0x02 与 BLE_BEGIN 0x10 是不同流程：前者会保存 nonce 并重启到旧 Wi-Fi SoftAP，BLE OTA 必须直接使用 BLE_BEGIN，不能在 BLE 流程前调用 PREPARE。

## 验证边界

单元测试覆盖签名/哈希/主机/布局/回滚错误、坏 ACK、丢 ACK、断点、偏移协调、提交响应丢失和版本确认。生产私钥、服务器/CDN、真实 ESP32 掉电/断线恢复和最终发布公钥不在本包中，也不能用假网络测试替代。

~~~
swift test --package-path ios/Packages/MauryaOTA -c debug
swift test --package-path ios/Packages/MauryaOTA -c release
~~~
