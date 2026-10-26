# 一期实现计划

依据：[Gimme Remote：一期需求与技术方案](https://bytedance.larkoffice.com/docx/BsVLdjTurondUQx376nc2WFJnfh)，revision 8。

直接在 master 开发，按三个交付块推进，不另外拆分任务分支。

1. **遥控主链路（M1）**：Swift 菜单栏 App、Hummingbird HTTP/WebSocket、共享协议；独立 Preact/Vite 手机页面；触控板、中文文本、IINA/浏览器按键、前台应用状态。验收：构建与自动测试通过，再在真实 IINA/Safari/Chrome、iPhone 与 HDMI 电视上验证。
2. **长期使用（M2）**：一次性二维码/六位码配对、Keychain 设备令牌、Origin 校验、限速、撤销与暂停；辅助功能引导、锁屏状态、重连、登录启动、防休眠；本机 CLI `gimme status/pair/stop`。验收：未认证/撤销设备不能输入，锁屏及权限缺失有明确错误，断线结束拖动和长按。
3. **发布交付**：统一构建脚本、固定 Bundle ID 与签名、GitHub Actions 测试；master push（含 PR merge）发布测试安装包，版本 tag 发布正式安装包并更新 `lucientong/homebrew-tap` 的 Cask。验收：arm64/x86_64 构建、签名校验、发布资产与 Cask 校验和一致。

**M3 截图点击**按原文作为可选后续增强，不纳入首次可用版本；协议拒绝尚未实现的截图请求，不申请屏幕录制权限。

## 工程决策

- macOS 14+；Swift Package 管理 Mac 工程，可直接在 Xcode 打开 `mac/Package.swift`。不额外维护重复的 `.xcodeproj`；发布脚本组装 App bundle。
- 前端源码独立，发布时打包到 `Contents/Resources/Web`；生产无需 Node 或外部 CDN。
- HTTP 与 WebSocket 同端口；设备令牌通过认证消息传递，不放入 URL。二维码配对码放在 URL fragment，成功后移除。
- 浏览器支持 Safari/Chrome 的通用快捷键；视频网站不承诺统一播放器快捷键，保留触控板完成兜底操作。
- 不存在服务器“测试环境”；master 的安装包是 GitHub prerelease，正式版本是非 prerelease 的 GitHub Release。
- 使用 Homebrew **Cask** 安装 App，并同时链接 `gimme`。正式 tag 格式 `vMAJOR.MINOR.PATCH`；带后缀的 tag 为预发布且不更新正式 Cask。
- 公开分发必须配置 Developer ID Application 证书和公证；本地开发使用固定 Apple Development/自签名身份。不自动退化成 ad-hoc 签名。

## 外部配置依赖

GitHub 签名证书、公证凭据、跨仓库 tap 写权限不在仓库内。流程与具体配置见 `docs/releasing.md`。未配置时 CI 仍运行测试和构建验证，但不能发布可安装的签名 App。首次正式 Release 产生真实 URL/SHA256 后才更新 Cask，不写假版本或假校验和。

## 实机验收

- IINA：播放、暂停、进度、音量、静音、全屏；长按松开后不再继续。
- Safari/Chrome：优酷、腾讯视频、YouTube；触控板选片、中文和 emoji；地址栏、标签页、前后导航。
- iPhone：单指移动/点击、双指滚动/右键、长按拖动；锁屏返回、网络断开和重连。
- Mac：辅助功能拒绝/撤销、系统锁屏、App 重启、登录启动、睡眠唤醒；镜像及扩展显示。
- 安全：错误配对码、过期/重复使用码、撤销令牌、错误 Origin、超大消息、高频突发。

## 当前交付验证

M1/M2 的代码及发布流程已实现。已通过前端 6 项测试、Homebrew 生成器 3 项测试、核心安全检查、真实 HTTP/WebSocket 检查（含大文本帧及撤销）、本机 Chrome 手机尺寸页面检查，以及 arm64/x86_64 universal App 结构验证。依赖审计与 Actions 语法检查通过。

本机仅有 Command Line Tools，完整 Swift Testing suite 由 CI 的 Xcode 环境运行。本机没有签名身份，签名、公证、真实 Homebrew 安装和上面的 IINA/iPhone/HDMI/权限矩阵仍需配置凭据及实机验收；没有将未签名构建当作正式安装包交付。
