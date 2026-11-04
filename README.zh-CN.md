# gimme-remote

[English](README.md) | **简体中文**

**用手机遥控接在电视上的 Mac。** 扫码即用，无需安装 App，局域网直连。Mac 端是 Swift 原生菜单栏 App，手机端是它在局域网内提供的网页。

支持：播放控制（IINA / 浏览器）、触控板（含双击、滚动、拖动）、中文整段输入、浏览器快捷键、二维码配对、Keychain 保存的设备令牌、权限与锁屏提示、断线重连、登录启动、连接时防休眠，以及本机 `gimme` CLI。

后续计划：截图点击、单台设备管理、英文界面。

## 安装

使用 Homebrew 安装：

```bash
brew install --cask lucientong/tap/gimme-remote
open -a GimmeRemote
```

也可以直接从 [GitHub Releases](https://github.com/lucientong/gimme-remote/releases/latest) 下载：展开 **Assets**，下载 `GimmeRemote-<版本>-universal.zip`，解压后将 `GimmeRemote.app` 拖入“应用程序”，再从“应用程序”中打开。一个 ZIP 同时支持 Apple Silicon 与 Intel，无需安装 Homebrew 或 Node。

体验最新测试版本可下载 [testing Release](https://github.com/lucientong/gimme-remote/releases/tag/testing)。它在 `master` 检查通过后更新，可能包含尚未进入正式版的改动。

打开菜单栏 App，授权“辅助功能”；手机与 Mac 连接同一 Wi-Fi 后扫描二维码。想从主屏幕使用时，请先在手机 Chrome 中“分享 → 添加到主屏幕”，再从主屏幕图标打开并在其中输入配对码：iOS 的主屏幕网页与浏览器分开存储，在 Chrome 中完成的配对不会带过去。

音量按钮调节 **播放器音量**，电视总音量仍用电视遥控器。网页播放器快捷键受页面焦点与网站支持影响，始终可用触控板点击电视画面里的控件。不使用 Service Worker、云中继或任意脚本执行。

浏览器工具栏的 **网页前进 / 后退** 切换浏览历史（⌘] / ⌘[）；没有更新的历史记录时，“前进”不会发生跳转。播放器的 **快进 / 快退** 发送右 / 左方向键。仅在当前网页播放器的辅助功能树中识别到播放按钮旁的对应控件时，显示 **上一集 / 下一集** 图标，并直接调用网页按钮；首尾集的禁用状态同步保留。识别沿用已有辅助功能授权，依赖浏览器和网站提供带名称的控件；无法识别或存在多个候选播放器时不显示上下集按钮。

请在可信的家庭网络中使用。遥控页面在局域网内以明文 HTTP 提供，依靠一次性配对码与每台设备的令牌保护，而非 TLS；避免在公共或共享 Wi-Fi 中使用。

要求 macOS 14+。发布包是 arm64 / Intel universal App，不使用 Apple Developer ID，经 GitHub Release 分发，未经过 Apple 公证。

首次打开若被 macOS 拦截，到“系统设置 → 隐私与安全 → 仍要打开”确认 GimmeRemote，并授予辅助功能权限。更新后若 GimmeRemote 在列表中仍显示已打开但输入无效：在“隐私与安全 → 辅助功能”中选中它，点 **−** 删除，再重新添加或重新打开 App。

## 开发

需要 Swift 6.2+、Node 22.12+。完整原生测试需要 Xcode；Command Line Tools 可编译与运行核心安全检查。

```bash
npm --prefix web ci
npm --prefix web test
npm --prefix web run build
swift build --package-path mac --jobs 4 --disable-index-store
bash scripts/test-core.sh
swift run --package-path mac --jobs 4 --disable-index-store TransportChecks

# 完整 Xcode 环境
swift test --package-path mac --jobs 4
```

`TransportChecks` 使用临时页面与内存令牌运行真实 HTTP/WebSocket 验证，不访问个人 Keychain，也不注入系统输入。

在 Xcode 中打开 `mac/Package.swift` 调试原生 App，保持 Bundle ID `com.lucientong.GimmeRemote` 一致。安装、输入权限与登录启动应在 `scripts/build-release.sh` 生成的 App bundle 中验证；不要将裸 SPM 可执行文件当作安装版本。

前端独立热更新：

```bash
npm --prefix web run dev
```

只查看前端 UI 时，打开 Vite 地址后的 `/?preview=browser`（默认 `http://localhost:5173/?preview=browser`），或点击页面顶部的“预览遥控界面”。也可以用 `npm --prefix web run dev:preview` 启动并自动打开预览。无需服务端、配对或局域网连接；预览可切换分集、单视频、首尾集、IINA、通用、暂停和锁屏状态，按钮不会发送操作到 Mac。入口仅在 Vite 开发模式提供，正式版不启用。

`TransportChecks` 是运行后退出的 HTTP/WebSocket 回归测试，监听的 `19371` 端口仅用于测试；它不是供前端连接的常驻原生服务端。

App 默认服务端口为 `9271`；Vite 的 `/ws` 代理指向 `127.0.0.1:9271`。原生开发时设置：

```text
GIMME_WEB_ROOT=/absolute/path/to/gimme-remote/web/dist
GIMME_DEV_ORIGINS=http://localhost:5173,http://192.168.1.2:5173
```

第二个 Origin 替换为运行 Vite 的 Mac 实际局域网 IP；开发白名单必须显式填写。手机访问 Vite 需要地址中的 Mac IP。也可用 `VITE_REMOTE_URL=http://mac.local:9271` 直接连接原生服务，但仍需把 Vite 页面的 Origin 加入开发白名单。

发布构建把 `web/dist` 复制到 `GimmeRemote.app/Contents/Resources/Web`，页面与 WebSocket 同源，生产不需要 Node。网络切换后菜单栏更新主机地址；新局域网 IP 的页面可能需要重新配对，优先保存稳定的 `.local` 地址。

## CLI

```bash
gimme status   # 服务、权限、连接数和访问地址
gimme pair     # 更新一次性配对码并输出地址
gimme stop     # 暂停远程输入
gimme resume   # 恢复远程输入
gimme --version
```

CLI 使用当前用户私有目录下的 Unix socket。菜单栏支持暂停、断开设备、撤销全部配对、登录启动与连接期间防休眠。暂停时手机保持连接并显示“已暂停”，恢复后继续遥控；断开设备会保留配对，需在手机上点击“重新连接”；撤销配对则需要重新扫码配对。

## 发布

PR 运行检查；master push（包括合并 PR）在检查通过后发布 `testing` 预发布版；`vMAJOR.MINOR.PATCH` 发布正式 Release 并更新 Homebrew tap。带预发布后缀的 tag 发布预发布版，不更新正式 Cask。

构建不需要 Apple Developer 会员。唯一必需的 repository secret 是 `lucientong/gimme-remote` 中的 `HOMEBREW_TAP_TOKEN`：使用 fine-grained GitHub PAT，只授权 **`lucientong/homebrew-tap`** 的 **Contents: Read and write**。GitHub Release 的发布令牌由 GitHub 自动提供。

发布包默认 ad-hoc 签名，每次更新后 macOS 可能让辅助功能授权失效。如需保留，可把一张自签名代码签名证书配置为两个可选 secret：`MACOS_SIGNING_P12_BASE64`（`.p12` 的 base64）与 `MACOS_SIGNING_P12_PASSWORD`。该证书无需 Apple 账号，只需在各版本间保持不变；私钥不要放入仓库。

在 macOS 上本地打包：

```bash
bash scripts/build-release.sh
```

默认在 `build/` 下生成 universal `GimmeRemote.app`、ZIP 和 `SHA256SUMS`。再次构建时用 `GIMME_OUTPUT_DIR` 指定新目录，脚本不会替换已存在的 App。设置 `GIMME_SIGNING_IDENTITY`（可选 `GIMME_SIGNING_KEYCHAIN`）可改用固定身份签名。`--unsigned` 只验证 bundle 结构，不生成发布 ZIP。

## 工程

```text
mac/        Swift 原生 App、服务、输入、CLI 和核心测试
web/        Preact / TypeScript / Vite 手机界面
shared/     JSON Schema 协议
scripts/    构建、核心检查与 Homebrew Cask 生成
```

浏览器、iPhone、HDMI 显示与系统权限的真实行为需要实机验收，自动测试不等同于播放器全场景验收。

图标由 `swift scripts/make-icons.swift` 生成（`mac/AppIcon.icns` 与 `web/public/icons/`），修改后重新运行并提交产物。

名字来自英文口语 *gimme the remote*（遥控器给我）。
