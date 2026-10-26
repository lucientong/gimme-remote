# gimme-remote

[English](README.md) | **简体中文**

**遥控器给我。** Mac 接电视，手机当遥控器。Swift 原生菜单栏 App + 局域网手机网页，无需安装 iOS App。

一期已实现播放器遥控、触控板、中文文本输入、IINA / 浏览器快捷键、二维码配对、Keychain 令牌、权限提示、锁屏提示、重连、登录启动、防休眠和本机 `gimme` CLI。截图点击为后续可选增强。

## 安装

首次稳定版发布并同步 tap 后：

```bash
brew tap lucientong/tap
brew install --cask lucientong/tap/gimme-remote
open -a GimmeRemote
```

打开菜单栏 App，授权“辅助功能”；手机与 Mac 连接同一 Wi-Fi 后扫描二维码，输入配对码并连接。Safari 可通过“分享 → 添加到主屏幕”保存入口。

音量按钮调节 **播放器音量**，电视总音量仍用电视遥控器。网页播放器快捷键受页面焦点与网站支持影响，始终可用触控板点击电视画面里的控件。不使用 Service Worker、云中继或任意脚本执行。

要求 macOS 14+。发布包是 arm64 / Intel universal App，使用免费 ad-hoc 签名，经 GitHub Release 分发，未经过 Apple 公证。

首次打开若被 macOS 拦截，到“系统设置 → 隐私与安全 → 仍要打开”确认 GimmeRemote，并授予辅助功能权限。更新后，macOS 可能要求重新授予辅助功能权限。

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
gimme stop     # 暂停远程输入；从菜单栏恢复
```

CLI 使用当前用户私有目录下的 Unix socket。菜单栏支持暂停、断开设备、撤销全部配对、登录启动与连接期间防休眠。

## 发布

PR 运行检查；master push（包括合并 PR）在检查通过后发布 `testing` 预发布版；`vMAJOR.MINOR.PATCH` 发布正式 Release 并更新 Homebrew tap。带预发布后缀的 tag 发布预发布版，不更新正式 Cask。

构建采用 ad-hoc 签名，不需要 Apple Developer 会员或 Apple Secrets。唯一需要手动设置的 repository secret 是 `lucientong/gimme-remote` 中的 `HOMEBREW_TAP_TOKEN`：使用 fine-grained GitHub PAT，只授权 **`lucientong/homebrew-tap`** 的 **Contents: Read and write**。GitHub Release 的发布令牌由 GitHub 自动提供。

在 macOS 上本地打包：

```bash
bash scripts/build-release.sh
```

默认在 `build/` 下生成 universal `GimmeRemote.app`、ZIP 和 `SHA256SUMS`。再次构建时用 `GIMME_OUTPUT_DIR` 指定新目录，脚本不会替换已存在的 App。`--unsigned` 只验证 bundle 结构，不生成发布 ZIP。

## 工程

```text
mac/        Swift 原生 App、服务、输入、CLI 和核心测试
web/        Preact / TypeScript / Vite 手机界面
shared/     JSON Schema 协议
scripts/    构建、核心检查与 Homebrew Cask 生成
```

浏览器、iPhone、HDMI 显示与系统权限的真实行为需要实机验收，自动测试不等同于播放器全场景验收。
