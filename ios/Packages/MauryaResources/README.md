# MauryaResources 应援色与头像资源

本包管理内置企划/分组/角色目录、用户自定义颜色和 Android 兼容备份。领域和持久化使用 Swift，Sources/CWebP 中固定的 libwebp 源码负责生成 Android 兼容的头像 WebP。

## 内置目录

当前资源快照包含 4 个企划、55 个分组、505 个角色和 560 个唯一引用的 PNG。asset_inventory.json 记录稳定 ID、中日名称、所属、应援色、路径、SHA-256、来源和审核状态；测试会校验目录哈希、ID、颜色、文件和每张图片哈希。

这些角色和标识属于原权利方，收录不表示授权。当前代码按本地安装场景启用资源；若以后扩展到公开、商业、TestFlight 或 App Store 分发，必须重新做资源和商标审核。

## 自定义头像和颜色

- AvatarImageProcessor 会先按方向解码，支持方形裁切、平移、缩放和 90 度旋转，再编码为 96×96 WebP。
- AvatarValidator 限制 RIFF 结构、首个图像 chunk（VP8/VP8L/VP8X）、96×96 尺寸和 6144 字节上限，并可校验 SHA-256。
- CustomPaletteRepository 是 actor，限制双语名称、#RRGGBB、版本、50 条上限、内容去重、哈希文件名、原子索引和删除撤销；损坏或孤立头像会在后续 loadAndRepair 中清理。
- schema-v1 备份字段与 Android 一致：id、nameZh、nameJa、hex、createdAt、updatedAt、avatarWebpBase64、avatarSha256。

## 验证

~~~
swift test --package-path ios/Packages/MauryaResources -c debug
swift test --package-path ios/Packages/MauryaResources -c release
~~~

包测试覆盖目录、头像结构、裁切/编码和自定义仓库；真实设备上的 ImageIO 解码、Android↔iPhone 备份往返、低磁盘、文件保护和安装包大小仍需单独验证。
