# 开发辅助脚本

tools/ 保存跨目录使用的构建和验证脚本，不包含服务器源码、发布包或固件镜像。

## 脚本

- build-unified-site.ps1：在本地网站工作区构建统一首页，并把 Maurya 下载页资源复制到本地预览目录。脚本依赖源码仓库之外的 src/server/xtbang-home 和 src/server/maurya-download，不能仅凭本仓库单独完成完整站点构建。
- verify-unified-site.ps1：检查统一站点的必需文件、链接和发布清单；适合发布前在拥有网站资源的工作区运行。
- render-maurya-block-demos.mjs：启动本地 Vite 编辑器资源，用 Playwright 加载红绿蓝、彩虹、42 颗逐灯彩虹、传感器分支、音乐频段和列表/函数示例，并输出截图与 block-demos.json。

## 编辑器演示脚本

渲染脚本使用 android/app/src/main/assets/effect-editor 的构建资源，要求 Node.js、该资源可读取以及 Playwright Chromium。若编辑器源码有改动，先按 android/effect_editor/README.md 重新构建，再执行渲染。脚本中的逐灯示例明确遍历 42 颗灯，不能改成其他数量。

这些脚本主要服务本地开发和发布准备；公开仓库不承诺在没有私有网站资源、固件包或签名材料的环境中直接生成最终下载页。
