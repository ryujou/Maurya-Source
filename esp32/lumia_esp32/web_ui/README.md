# ESP32 板端网页源码

本目录是固件内置网页控制台的 Vue 3 + Vite 源码。网页在固件中离线运行，设备运行时不需要 Node.js；构建出的静态文件由固件资源打包脚本写入 Flash。

## 常用命令

~~~
npm ci
npm run build
npm test
python ..\tools\build_web_assets.py
~~~

npm run build:ja 构建日文变体，npm run test:ja 校验日文资源。public/palette.json 等紧凑资源会被固件直接读取并受测试保护；网页通过固件提供的 HTTP API 读取设备状态、发送灯效/寄存器操作和访问 OTA 页面。
