# Maurya 固件标准发布流程

本文档是 Maurya ESP32-C3 固件的固定发布操作手册。以后每次正式发布均按本文执行，不跳过签名、双语言构建、产物校验或真机验证。

## 1. 固定发布范围

每个版本必须同时生成以下内容：

- 多语言固件和日文固件。
- 两个 Windows 单文件一键烧录 EXE。
- 两个包含 EXE、四镜像、清单、说明书和 SHA-256 的离线 ZIP。
- 与 GitHub 历史发布一致的 8 个独立 BIN。
- 多语言和日文两套 BLE OTA 服务端文件。
- GitHub 发布资产总 `SHA256SUMS.txt`。

固定硬件与工具基线：

| 项目 | 固定值 |
|---|---|
| MCU | ESP32-C3 |
| Flash | 4 MB |
| ESP-IDF | 6.0.1 |
| esptool | 5.3.0，烧录器打包时必须精确匹配 |
| 灯珠布局 | 7 组 × 6 颗 = 42 颗 |
| Wi-Fi 最大发射功率 | 8.5 dBm，即 ESP-IDF 参数 34 |
| BLE 发射功率 | 6 dBm，即 `ESP_PWR_LVL_P6` |
| 多语言版本格式 | `X.Y.Z` |
| 日文版本格式 | `X.Y.Z-jp` |

## 2. 正式发布 Gate

正式发布必须同时满足：

- 发布改动已经提交，`git status --porcelain` 为空。
- 发布使用精确 Git 提交 SHA，禁止使用 `dirty` 标记的预览产物上传 GitHub 或 OTA 服务器。
- 新 `secureVersion` 严格大于线上版本。推荐每次加 1；不得复用或回退。
- 正式 RSA 私钥的公钥指纹与 Android、iOS 内置 OTA 公钥一致。
- 私钥未进入 Git、构建产物、ZIP、日志或校验清单。
- 两个固件均完成 ESP-IDF 全量构建。
- 两个 EXE 的 `--smoke-test` 均通过。
- ZIP、四镜像、OTA 哈希和 OTA RSA 签名均通过校验。
- 真机完成 USB 全量烧录、BLE OTA、Wi-Fi、BLE 和 42 灯验证。

允许从未提交工作树生成内部预览包，但必须在 `flash-manifest.json` 的提交字段末尾标记 `-dirty`，并且不得对外发布。

## 3. 发布产物和固定命名

假设版本为 `1.8.2`，发布目录结构固定如下：

```text
Maurya-Release-v1.8.2/
├── Maurya-v1.8.2.zip
├── Maurya-JP-v1.8.2-jp.zip
├── multilingual/
│   ├── Maurya_Flasher_v1.8.2.exe
│   ├── 使用说明.md
│   ├── SHA256SUMS.txt
│   └── firmware/
│       ├── bootloader.bin
│       ├── partition-table.bin
│       ├── lumia_esp32.bin
│       ├── assetsfs.bin
│       └── flash-manifest.json
├── ja/
│   ├── Maurya_JP_Flasher_v1.8.2-jp.exe
│   ├── 取扱説明書.md
│   ├── SHA256SUMS.txt
│   └── firmware/...
├── github-assets/
│   ├── Maurya-v1.8.2.zip
│   ├── Maurya-JP-v1.8.2-jp.zip
│   ├── maurya-1.8.2-multi-bootloader.bin
│   ├── maurya-1.8.2-multi-partition-table.bin
│   ├── maurya-1.8.2-multi-firmware.bin
│   ├── maurya-1.8.2-multi-assetsfs.bin
│   ├── maurya-1.8.2-jp-bootloader.bin
│   ├── maurya-1.8.2-jp-partition-table.bin
│   ├── maurya-1.8.2-jp-firmware.bin
│   ├── maurya-1.8.2-jp-assetsfs.bin
│   └── SHA256SUMS.txt
└── ota/stable/
    ├── multilingual/
    │   ├── manifest.json
    │   ├── manifest.sig
    │   ├── maurya-1.8.2.bin
    │   └── maurya-1.8.2.bin.sha256
    └── ja/
        ├── manifest.json
        ├── manifest.sig
        ├── maurya-1.8.2-jp.bin
        └── maurya-1.8.2-jp.bin.sha256
```

一键烧录器固定写入地址：

| 镜像 | 地址 |
|---|---:|
| `bootloader.bin` | `0x0` |
| `partition-table.bin` | `0x8000` |
| `lumia_esp32.bin` | `0x20000` |
| `assetsfs.bin` | `0x240000` |

烧录器必须整片擦除，使用 DIO、80 MHz、460800 baud，并在写入后校验镜像和 USB Serial Modbus 地址 1。

## 4. 发布前版本更新

先确定新版本和单调安全版本。例如：

```powershell
$version = '1.8.2'
$jpVersion = "$version-jp"
$secureVersion = 182
```

至少检查并更新以下位置：

- `esp32/lumia_esp32/CMakeLists.txt` 中的 `PROJECT_VER` 和 `MAURYA_SECURE_VERSION`。
- `esp32/lumia_esp32/web_ui/package.json` 与 `package-lock.json`。
- `esp32/lumia_esp32/web_ui/src/App.vue` 中显示的两个版本。
- `esp32/lumia_esp32/web_ui/tools/verify-build.mjs`。
- `esp32/lumia_esp32/tools/test_web_assets.py`。
- `esp32/lumia_esp32/tools/build_ota_release.py` 中的双语发布说明。
- `esp32/lumia_esp32/tools/production_flasher/README.zh.md`。
- `esp32/lumia_esp32/tools/production_flasher/README.ja.md`。
- `esp32/lumia_esp32/tools/production_flasher/README.md`。
- 根目录 `README.md` 和 `SOURCE_VERSIONS.md`。

可以在 Web UI 目录用下面的命令同步两个 npm 版本文件：

```powershell
cd esp32\lumia_esp32\web_ui
npm version $version --no-git-tag-version
```

不要修改 iOS 中专门兼容已发布 `1.8.0` 签名清单的历史兼容代码，除非该兼容策略本身发生变化。

版本更新完成后执行源码测试并提交。正式构建开始前再次确认：

```powershell
git status --porcelain
git log -1 --oneline
```

第一条命令必须没有输出。

## 5. 环境与私钥预检

在当前 Windows 发布机上使用 PowerShell 7：

```powershell
$repoRoot = 'G:\ChatGPT\Maurya-GitHub-Incremental'
$project = Join-Path $repoRoot 'esp32\lumia_esp32'
$releaseRoot = "G:\ChatGPT\Maurya-Release-v$version"
$python = 'C:\Espressif\tools\python\v6.0.1\venv\Scripts\python.exe'
$idfProfile = 'C:\Espressif\tools\Microsoft.v6.0.1.PowerShell_profile.ps1'
$privateKey = Join-Path $project 'keys\maurya-release-signing-key.pem'

. $idfProfile
idf.py --version
& $python -c "import importlib.metadata as m; print('esptool', m.version('esptool')); print('PyInstaller', m.version('PyInstaller')); print('cryptography', m.version('cryptography'))"
```

`esptool` 必须为 `5.3.0`。`build_release.py` 会再次强制检查。

正式私钥应临时放在上述 `$privateKey` 路径；`keys/*.pem` 已被 Git 忽略。私钥应来自受控备份，不得新生成替代，否则旧固件和 App 无法信任新 OTA。

用 Android 内置公钥核对指纹：

```powershell
$env:MAURYA_PRIVATE_KEY = $privateKey
$env:MAURYA_PUBLIC_KEY = Join-Path $repoRoot 'android\app\src\main\res\raw\maurya_ota_public_key.pem'
@'
import hashlib, os
from pathlib import Path
from cryptography.hazmat.primitives import serialization

def public_der(path: str, private: bool) -> bytes:
    data = Path(path).read_bytes()
    key = (serialization.load_pem_private_key(data, password=None).public_key()
           if private else serialization.load_pem_public_key(data))
    return key.public_bytes(
        serialization.Encoding.DER,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    )

private_hash = hashlib.sha256(public_der(os.environ['MAURYA_PRIVATE_KEY'], True)).hexdigest()
public_hash = hashlib.sha256(public_der(os.environ['MAURYA_PUBLIC_KEY'], False)).hexdigest()
print('private-derived public:', private_hash)
print('app public:', public_hash)
assert private_hash == public_hash, 'release key does not match the app public key'
'@ | & $python -
```

## 6. 构建多语言 Web 和固件

先构建多语言 Web，并将压缩资源写入固件源码目录：

```powershell
cd (Join-Path $project 'web_ui')
npm ci
npm run build
npm test
& $python '..\tools\build_web_assets.py'
```

然后使用仓库外的独立构建目录生成正式签名固件：

```powershell
New-Item -ItemType Directory -Path $releaseRoot -Force | Out-Null
cd $project
idf.py -B (Join-Path $releaseRoot 'build-multilingual') `
  -D "SDKCONFIG=$releaseRoot/sdkconfig.multilingual" `
  -D "SDKCONFIG_DEFAULTS=sdkconfig.defaults" `
  -D "PROJECT_VER=$version" `
  -D "MAURYA_SECURE_VERSION=$secureVersion" `
  build
```

构建日志必须出现：

- `App "lumia_esp32" version: X.Y.Z`。
- `Generating signed binary image`。
- 应用镜像未超过最小 OTA 分区。

## 7. 构建日文 Web 和固件

日文资源必须单独构建，不能复用多语言 `assetsfs.bin`：

```powershell
cd (Join-Path $project 'web_ui')
npm run build:ja
npm run test:ja
& $python '..\tools\build_web_assets.py'

cd $project
idf.py -B (Join-Path $releaseRoot 'build-ja') `
  -D "SDKCONFIG=$releaseRoot/sdkconfig.ja" `
  -D "SDKCONFIG_DEFAULTS=sdkconfig.defaults;sdkconfig.ja.defaults" `
  -D "PROJECT_VER=$jpVersion" `
  -D "MAURYA_SECURE_VERSION=$secureVersion" `
  build
```

日文固件完成后，必须把源码树恢复为默认多语言 Web 资源：

```powershell
cd (Join-Path $project 'web_ui')
npm run build
npm test
& $python '..\tools\build_web_assets.py'
```

## 8. 生成两个一键烧录器和离线 ZIP

正式发布使用干净工作树的完整提交 SHA：

```powershell
$commit = (git -C $repoRoot rev-parse HEAD).Trim()
if (git -C $repoRoot status --porcelain) {
    throw 'Formal release requires a clean working tree'
}

cd $project
& $python 'tools\production_flasher\build_release.py' `
  --project $project `
  --build (Join-Path $releaseRoot 'build-multilingual') `
  --output (Join-Path $releaseRoot 'multilingual') `
  --commit $commit `
  --version $version `
  --variant multilingual

& $python 'tools\production_flasher\build_release.py' `
  --project $project `
  --build (Join-Path $releaseRoot 'build-ja') `
  --output (Join-Path $releaseRoot 'ja') `
  --commit $commit `
  --version $jpVersion `
  --variant ja
```

脚本会自动：

- 将四个固定镜像和 `flash-manifest.json` 内置进 EXE。
- 生成对应语言说明书。
- 生成包内 `SHA256SUMS.txt`。
- 运行 EXE `--smoke-test`。
- 生成两套 ZIP。

注意：脚本会删除并重建指定的 `--output` 目录，因此输出必须是确认无误的仓库外版本目录，禁止指向源码仓库或其他资料目录。

## 9. 生成 OTA 文件

```powershell
& $python 'tools\build_ota_release.py' `
  --project $project `
  --build (Join-Path $releaseRoot 'build-multilingual') `
  --output (Join-Path $releaseRoot 'ota\stable\multilingual') `
  --variant multilingual `
  --version $version `
  --secure-version $secureVersion `
  --private-key $privateKey

& $python 'tools\build_ota_release.py' `
  --project $project `
  --build (Join-Path $releaseRoot 'build-ja') `
  --output (Join-Path $releaseRoot 'ota\stable\ja') `
  --variant ja `
  --version $jpVersion `
  --secure-version $secureVersion `
  --private-key $privateKey
```

确认两个 `manifest.json` 中的版本、`secureVersion`、下载 URL、大小、SHA-256 和双语发布说明均正确。

## 10. 生成 GitHub 历史同规格裸 BIN

```powershell
$assets = Join-Path $releaseRoot 'github-assets'
New-Item -ItemType Directory -Path $assets -Force | Out-Null

Copy-Item -LiteralPath (Join-Path $releaseRoot "Maurya-v$version.zip") -Destination $assets
Copy-Item -LiteralPath (Join-Path $releaseRoot "Maurya-JP-v$jpVersion.zip") -Destination $assets

$copies = @(
    @('build-multilingual\bootloader\bootloader.bin', "maurya-$version-multi-bootloader.bin"),
    @('build-multilingual\partition_table\partition-table.bin', "maurya-$version-multi-partition-table.bin"),
    @('build-multilingual\lumia_esp32.bin', "maurya-$version-multi-firmware.bin"),
    @('build-multilingual\assetsfs.bin', "maurya-$version-multi-assetsfs.bin"),
    @('build-ja\bootloader\bootloader.bin', "maurya-$version-jp-bootloader.bin"),
    @('build-ja\partition_table\partition-table.bin', "maurya-$version-jp-partition-table.bin"),
    @('build-ja\lumia_esp32.bin', "maurya-$version-jp-firmware.bin"),
    @('build-ja\assetsfs.bin', "maurya-$version-jp-assetsfs.bin")
)

foreach ($copy in $copies) {
    Copy-Item -LiteralPath (Join-Path $releaseRoot $copy[0]) `
      -Destination (Join-Path $assets $copy[1])
}

$hashLines = Get-ChildItem -LiteralPath $assets -File |
  Sort-Object Name |
  ForEach-Object {
      $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLowerInvariant()
      "$hash  $($_.Name)"
  }
Set-Content -LiteralPath (Join-Path $assets 'SHA256SUMS.txt') `
  -Value $hashLines -Encoding utf8NoBOM
```

## 11. 自动校验

至少执行：

```powershell
cd $project
$env:PYTHONPATH = Join-Path $project 'tools'
& $python -m unittest production_flasher.test_core
& $python 'tools\test_flash_layout.py'
& $python 'tools\test_web_assets.py'

& (Join-Path $releaseRoot "multilingual\Maurya_Flasher_v$version.exe") --smoke-test
& (Join-Path $releaseRoot "ja\Maurya_JP_Flasher_v$jpVersion.exe") --smoke-test

& $python -m esptool image-info `
  (Join-Path $releaseRoot 'build-multilingual\lumia_esp32.bin')
& $python -m esptool image-info `
  (Join-Path $releaseRoot 'build-ja\lumia_esp32.bin')
```

同时按 [`tests/host/README.md`](../lumia_esp32/tests/host/README.md) 运行全部 GCC 主机测试，包括协议运行时、灯效会话、配置存储、灯效引擎、LED 路由、模式按键和休眠开关。不能只运行其中一项。

`image-info` 必须分别显示：

- `App version: X.Y.Z` 和 `App version: X.Y.Z-jp`。
- 相同且正确的新 `Secure version`。
- `Validation hash: ... (valid)`。

用 Android 内置公钥验证两个 `manifest.sig`，重新计算 OTA BIN 的 SHA-256，并执行 ZIP 完整性检查：

```powershell
$env:MAURYA_RELEASE_ROOT = $releaseRoot
$env:MAURYA_PUBLIC_KEY = Join-Path $repoRoot 'android\app\src\main\res\raw\maurya_ota_public_key.pem'
$env:MAURYA_VERSION = $version
$env:MAURYA_JP_VERSION = $jpVersion
$env:MAURYA_SECURE_VERSION = "$secureVersion"
@'
import base64, hashlib, json, os, zipfile
from pathlib import Path
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding

root = Path(os.environ['MAURYA_RELEASE_ROOT'])
public_key = serialization.load_pem_public_key(
    Path(os.environ['MAURYA_PUBLIC_KEY']).read_bytes()
)

for archive in (root / f'Maurya-v{os.environ["MAURYA_VERSION"]}.zip',
                root / f'Maurya-JP-v{os.environ["MAURYA_JP_VERSION"]}.zip'):
    with zipfile.ZipFile(archive) as bundle:
        assert bundle.testzip() is None, f'corrupt ZIP: {archive}'

for variant, version in (('multilingual', os.environ['MAURYA_VERSION']),
                         ('ja', os.environ['MAURYA_JP_VERSION'])):
    folder = root / 'ota' / 'stable' / variant
    encoded = (folder / 'manifest.json').read_bytes()
    signature = base64.b64decode((folder / 'manifest.sig').read_text(encoding='ascii'))
    public_key.verify(signature, encoded, padding.PKCS1v15(), hashes.SHA256())
    manifest = json.loads(encoded)
    image = folder / f'maurya-{version}.bin'
    digest = hashlib.sha256(image.read_bytes()).hexdigest()
    assert digest == manifest['sha256']
    assert manifest['versionName'] == version
    assert manifest['secureVersion'] == int(os.environ['MAURYA_SECURE_VERSION'])

print('ZIP, OTA hash, version and RSA signature verification passed')
'@ | & $python -
```

任何一项失败都不得发布。

确认 42 灯配置已进入两个最终 sdkconfig：

```powershell
rg -n 'CONFIG_LUMIA_LED_CH[1-7]_COUNT=|CONFIG_LUMIA_LED_TX_PHYSICAL_MAX_COUNT=' `
  (Join-Path $releaseRoot 'sdkconfig.multilingual') `
  (Join-Path $releaseRoot 'sdkconfig.ja')
```

所有 16 个结果都必须为 `6`。

最后确认发布目录不存在私钥：

```powershell
Get-ChildItem -LiteralPath $releaseRoot -Recurse -File -Include *.pem,*.key
```

命令必须没有输出。校验完成后，从源码目录移除临时私钥，并确认 `keys` 路径没有被打包或提交。

## 12. 真机验证

自动校验通过后，至少选择一块 ESP32-C3 4 MB 实机完成：

1. 使用多语言 EXE 整片擦除并烧录。
2. 确认烧录器识别 ESP32-C3、4 MB Flash、四镜像校验成功以及 USB Modbus 地址 1。
3. 启动普通 BLE 模式，验证广播、连接、控制、通知、断开和重新广播。
4. 验证 7 路各 6 颗，逐灯控制总数为 42。
5. 启动 Wi-Fi SoftAP，验证网页、HTTP API 和两个客户端连接。
6. 从当前线上版本执行多语言 BLE OTA，确认升级、重启、回连和版本号。
7. 使用日文固件重复 USB 烧录与 OTA，确认日文 Web 资源没有串包。
8. 从日志确认 Wi-Fi 读取功率为参数 34（8.5 dBm），BLE 广播和连接功率为 6 dBm。
9. 固定距离、方向和设备，对比 RSSI 与有效距离，确认覆盖范围缩短且近距离控制稳定。

没有真机证据时，产物只能标记为“构建完成，待硬件验证”，不能标记为正式发布完成。

## 13. GitHub 与 OTA 服务器发布

只有自动校验和真机 Gate 全部通过后才能发布：

1. 创建与版本对应的 Git tag。
2. 创建 GitHub Release，上传 `github-assets/` 中的两个 ZIP、8 个 BIN 和 `SHA256SUMS.txt`。
3. 上传 `ota/stable/multilingual/` 和 `ota/stable/ja/` 的全部文件到对应服务器目录。
4. 更新服务器 `latest.json`、下载页文件名和版本号。
5. 先在临时路径上传，核对权限、所有者、SHA-256 和 Nginx 配置后再原子替换线上文件。
6. 用 Android 和 iOS 分别读取线上 manifest，完成一次真实下载和签名验证。
7. 保留 GitHub Release URL、提交 SHA、tag、SHA256SUMS、真机日志和 OTA 验证结果。

发布不会因为“文件已上传”自动判定成功。只有客户端能够获取、验证、升级并回连，才算发布完成。

## 14. 失败处理与禁止事项

- 构建失败：修复源码或环境后从对应语言的 Web 构建步骤重新开始。
- 签名失败：停止发布，核对正式私钥；禁止临时生成新密钥顶替。
- 哈希或 ZIP 校验失败：删除该版本输出目录后重新生成，不手工替换 ZIP 内单个文件。
- EXE 冒烟测试失败：不得只发布裸 BIN，先修复烧录器环境或代码。
- OTA `secureVersion` 不递增：重新确定版本并全量重建。
- 多语言与日文资源串包：从第 6 步开始重新构建两个变体。
- 工作树不干净：只允许生成内部预览包，不得上传。
- 未经明确授权，不自动推送 Git、创建 Release 或部署服务器。
- 禁止在聊天、工单、提交信息或构建日志中粘贴私钥内容。

## 15. 每次发布记录模板

```markdown
# Maurya firmware X.Y.Z release record

- Git commit:
- Git tag:
- Secure version:
- ESP-IDF:
- esptool:
- Multilingual firmware SHA-256:
- Japanese firmware SHA-256:
- Multilingual ZIP SHA-256:
- Japanese ZIP SHA-256:
- OTA manifest signature verified: yes/no
- EXE smoke tests: pass/fail
- Host tests: pass/fail
- ESP-IDF builds: pass/fail
- Hardware USB flash: pass/fail
- Hardware BLE OTA: pass/fail
- 42-pixel routing: pass/fail
- Wi-Fi 8.5 dBm read-back: pass/fail
- BLE 6 dBm read-back: pass/fail
- GitHub Release URL:
- OTA production verification:
- Operator:
- Date:
- Notes:
```
