# 发布与 Homebrew

## GitHub Actions

`.github/workflows/ci-release.yml` 的行为：

| 事件 | 行为 |
| --- | --- |
| PR → master | 前端类型检查、测试、构建、依赖审计；arm64 / Intel 原生编译与 Swift 测试 |
| master push（包括合并 PR） | 检查通过后构建 universal App；凭据齐全时签名、公证并替换 `testing` prerelease |
| `v1.2.3` tag | 检查、签名、公证、发布正式 GitHub Release，并更新 Homebrew tap |
| `v1.2.3-beta.1` tag | 发布 prerelease，不更新正式 Homebrew Cask |
| 手动运行 | 当前 ref 的检查与打包；master 对应 testing |

macOS 桌面工具没有独立服务器测试环境。测试包位于仓库 Releases 的 `testing`，不是部署到公网的网页。测试版与正式版使用相同 Bundle ID 和固定签名身份，安装时互相替换；升级前退出 App。

尚未设置签名、公证凭据时，master CI 只验证 universal App 打包，不上传未签名安装包。tag 发布会明确失败，避免把权限不稳定的构建当作正式版。前端和 Swift 测试不依赖这些凭据。

## 一次性 GitHub 配置

在 `lucientong/gimme-remote` → Settings → Secrets and variables → Actions 设置以下 **repository secrets**：

| Secret | 内容 |
| --- | --- |
| `MACOS_CERTIFICATE_P12_BASE64` | Developer ID Application 证书及私钥导出 `.p12` 的 base64 |
| `MACOS_CERTIFICATE_PASSWORD` | `.p12` 导出密码，使用非空密码 |
| `MACOS_SIGNING_IDENTITY` | 完整身份，如 `Developer ID Application: Your Name (TEAMID)` |
| `APPLE_ID` | 开发者 Apple ID |
| `APPLE_TEAM_ID` | Team ID |
| `APPLE_APP_PASSWORD` | Apple ID 的 app-specific password，供 notarytool 使用 |
| `HOMEBREW_TAP_TOKEN` | Fine-grained PAT：仅授权 `lucientong/homebrew-tap`，Contents: Read and write |

签名与公证需要 Mac 分发用 Apple Developer 身份。这与手机使用 Safari 无关，手机不需要开发者账号。证书、密码和 PAT 不应提交到 Git。

从钥匙串导出证书后，可用 `base64 -i signing.p12 | pbcopy` 复制编码。Actions 使用临时钥匙串导入，结束后删除证书及临时钥匙串。每次构建都使用同一身份与 `com.lucientong.GimmeRemote`。

流程使用 `testing` / `production` GitHub Environments。可以创建它们并设置环境限制；当前没有人工 approval gate。使用 repository secrets 可同时供打包和 tap 更新任务读取。给 testing 设置保护规则会导致 master 发布等待审批。

## 正式发布

```bash
# 在已经通过检查的 master commit 上打 tag。
git tag v0.1.0
git push origin v0.1.0
```

Release 包含：

- `GimmeRemote-0.1.0-universal.zip`：arm64 + x86_64 的签名、公证 App，内置网页与 CLI。
- `SHA256SUMS`：最终公证、staple 后的 ZIP 校验和。

正式 release 发布成功后，workflow 自动检出 `lucientong/homebrew-tap` 的 master，运行 `scripts/update-homebrew.py` 生成 `Casks/gimme-remote.rb`，以 rebase 更新 tap。只有稳定版更新 Cask，预发布不会覆盖正式安装渠道。

如果 tap 更新失败，正式 Release 仍保留。设置 token 后可以使用实际 Release ZIP 手动恢复：

```bash
git clone git@github.com:lucientong/homebrew-tap.git /tmp/gimme-homebrew-tap
python3 scripts/update-homebrew.py \
  --version 0.1.0 --tag v0.1.0 \
  --archive /path/to/GimmeRemote-0.1.0-universal.zip \
  --tap /tmp/gimme-homebrew-tap
# 在 tap checkout 内审查、提交 Casks/gimme-remote.rb，再 git pull --rebase / git push。
```

首次稳定版尚未发布时，tap 里不会有虚构的版本、下载 URL 或 SHA256，Homebrew 安装命令要等上述流程完成后才可用。

## Homebrew 安装

```bash
brew tap lucientong/tap
brew install --cask lucientong/tap/gimme-remote
open -a GimmeRemote
gimme status
gimme pair
gimme stop
```

Cask 安装 `GimmeRemote.app` 到 Applications，同时链接 App 内的 `gimme`。CLI 通过当前用户私有目录下的 Unix socket 请求 App，不注入输入；`gimme stop` 暂停远程输入，可在菜单栏恢复。

```bash
brew upgrade --cask lucientong/tap/gimme-remote
brew uninstall --cask lucientong/tap/gimme-remote
```

配对令牌保存在 Keychain，普通卸载保留配对。彻底清除前先从 App 菜单栏“撤销全部配对”；`brew uninstall --cask --zap` 清除配置和本机 socket 目录，不绕过 Keychain 权限删除其他钥匙串项。

## 本地打包

```bash
# 原生构建（无需签名）
swift build --package-path mac --jobs 4 --disable-index-store

# 完整 Xcode 下运行原生测试
swift test --package-path mac --jobs 4

# 只有 Command Line Tools 时运行核心安全检查
bash scripts/test-core.sh
swift run --package-path mac --jobs 4 --disable-index-store TransportChecks

# 固定签名开发构建，避免每次重新授予辅助功能权限
GIMME_SIGNING_IDENTITY='Apple Development: Your Name (TEAMID)' \
GIMME_ARCH=arm64 GIMME_OUTPUT_DIR=/tmp/gimme-local \
bash scripts/build-release.sh
```

`--unsigned` 仅用于验证 bundle 结构，不生成分发 ZIP，也不是推荐安装方式。打包目录要求不存在旧的 `GimmeRemote.app`，不会覆盖已经安装的 App。正式 universal 构建默认同时编译 arm64、x86_64；发布时追加 `--notarize` 并提供 Apple 凭据。
