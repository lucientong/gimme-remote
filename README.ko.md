# gimme-remote

[English](README.md) | [简体中文](README.zh-CN.md) | [日本語](README.ja.md) | **한국어**

**TV에 연결한 Mac을 휴대폰으로 조작하세요.** QR 코드를 스캔하면 로컬 네트워크에서 바로 사용할 수 있습니다. Mac의 Swift 네이티브 메뉴 막대 앱이 휴대폰용 웹 인터페이스를 제공합니다. iOS 앱을 설치할 필요가 없습니다.

지원 기능: IINA / 브라우저 재생 조작, 터치패드(더블 클릭, 스크롤, 드래그), Unicode 텍스트 입력, 브라우저 단축키, QR 코드 페어링, 키체인에 저장하는 기기별 토큰, 권한 및 잠금 상태 안내, 재연결, 로그인 시 실행, 연결 중 디스플레이 잠자기 방지, 중국어 / 영어 / 일본어 / 한국어 인터페이스, 로컬 `gimme` CLI.

향후 계획: 스크린샷을 통한 클릭과 기기별 관리.

## 설치

Homebrew로 설치:

```bash
brew install --cask lucientong/tap/gimme-remote
open -a GimmeRemote
```

[GitHub Releases](https://github.com/lucientong/gimme-remote/releases/latest)에서 직접 다운로드할 수도 있습니다. **Assets**를 펼쳐 `GimmeRemote-<version>-universal.zip`을 다운로드하고 압축을 푼 뒤, `GimmeRemote.app`을 **응용 프로그램** 폴더로 옮겨 실행하세요. 같은 ZIP이 Apple Silicon과 Intel을 모두 지원하며, Homebrew나 Node가 필요하지 않습니다.

최신 테스트 버전은 [testing 릴리스](https://github.com/lucientong/gimme-remote/releases/tag/testing)에서 받을 수 있습니다. `master`의 검사를 통과하면 갱신되며, 정식 버전에 아직 포함되지 않은 변경 사항이 있을 수 있습니다.

메뉴 막대 앱을 열고 손쉬운 사용 권한을 허용하세요. 휴대폰과 Mac을 같은 Wi-Fi에 연결한 뒤 QR 코드를 스캔합니다. 홈 화면에서 사용하려면 먼저 휴대폰 Chrome에서 **공유 → 홈 화면에 추가**를 선택하고, 추가한 아이콘을 열어 페어링 코드를 입력하세요. iOS의 홈 화면 웹 앱과 브라우저는 데이터를 별도로 저장하므로, Chrome에서 완료한 페어링이 홈 화면 앱으로 이어지지 않습니다.

Mac 앱과 휴대폰 인터페이스는 각각의 시스템 언어에 따라 중국어, 영어, 일본어, 한국어를 표시합니다. 다른 언어는 영어로 표시됩니다. 직접 변경하려면 Mac 패널의 **일반 → 언어**, 또는 휴대폰 페이지 상단의 연결 상태를 누른 뒤 **설정 → 언어**에서 선택하세요. 선택은 저장되며, 이미 표시된 오류 안내도 즉시 바뀝니다. 휴대폰에서는 페어링 전에도 언어를 바꿀 수 있고, 현재 연결과 입력 중인 텍스트는 유지됩니다. **시스템 설정 따르기**를 선택하면 자동 감지로 돌아갑니다. 중국어의 지역 및 문자 변형은 현재 모두 간체자로 표시됩니다.

음량 버튼은 **플레이어 음량**을 조절합니다. TV 전체 음량은 TV 리모컨으로 조절하세요. 웹 플레이어 단축키는 페이지의 포커스와 사이트 지원 여부에 따라 달라집니다. 터치패드로 TV 화면에 보이는 조작 버튼을 클릭할 수도 있습니다. Service Worker, 클라우드 중계, 임의의 스크립트 실행은 사용하지 않습니다.

브라우저의 **뒤로 / 앞으로**는 방문 기록을 이동합니다(⌘[ / ⌘]). 더 최신 기록이 없으면 “앞으로”를 눌러도 이동하지 않습니다. 플레이어의 **빨리 감기 / 되감기**는 오른쪽 / 왼쪽 방향키를 전송합니다. **이전 에피소드 / 다음 에피소드** 아이콘은 현재 웹 플레이어의 접근성 트리에서 재생·일시 정지 버튼 근처에 해당 조작 버튼이 식별될 때만 표시됩니다. 사이트의 버튼을 직접 호출하며, 첫 회나 마지막 회에서 비활성화된 버튼은 비활성 상태를 유지합니다. 기존 손쉬운 사용 권한을 사용하며, 브라우저와 사이트가 이름이 있는 조작 버튼을 제공해야 합니다. 식별하지 못하거나 여러 후보가 있으면 에피소드 버튼을 표시하지 않습니다.

신뢰할 수 있는 가정용 네트워크에서 사용하세요. 리모컨 페이지는 LAN에서 평문 HTTP로 제공되며, TLS가 아닌 일회용 페어링 코드와 기기별 토큰으로 보호됩니다. 공용 또는 공유 Wi-Fi에서는 사용을 피하세요.

macOS 14 이상이 필요합니다. 릴리스는 Apple Silicon / Intel을 지원하는 Universal 앱이며, Apple Developer ID 없이 GitHub Releases로 배포됩니다. Apple의 공증을 받지 않았습니다.

macOS가 첫 실행을 차단하면 **시스템 설정 → 개인정보 보호 및 보안 → 확인 없이 열기(Open Anyway)**에서 GimmeRemote 실행을 허용하세요. 원격 입력에는 손쉬운 사용 권한이 필요합니다. 업데이트 후 GimmeRemote가 켜져 있는데도 입력이 작동하지 않으면 **개인정보 보호 및 보안 → 손쉬운 사용** 목록에서 선택하고 **−**로 제거한 뒤 다시 추가하거나 앱을 다시 여세요.

## 개발

Swift 6.2 이상과 Node 22.12 이상이 필요합니다. 네이티브 테스트 전체를 실행하려면 Xcode가 필요합니다. Command Line Tools로도 앱을 빌드하고 핵심 보안 검사를 실행할 수 있습니다.

```bash
npm --prefix web ci
npm --prefix web test
npm --prefix web run build
swift build --package-path mac --jobs 4 --disable-index-store
bash scripts/test-core.sh
bash scripts/test-menu-panel.sh
swift run --package-path mac --jobs 4 --disable-index-store TransportChecks

# Xcode가 설치된 환경
swift test --package-path mac --jobs 4
```

`TransportChecks`는 임시 페이지와 메모리 내 토큰으로 실제 HTTP / WebSocket 동작을 검증합니다. 개인 키체인에 접근하거나 시스템 입력을 보내지 않습니다.

네이티브 앱을 디버깅하려면 Xcode에서 `mac/Package.swift`를 여세요. Bundle ID는 `com.lucientong.GimmeRemote`로 유지합니다. 설치, 입력 권한, 로그인 시 실행은 `scripts/build-release.sh`가 생성한 App 번들로 확인하세요. Swift Package Manager의 단독 실행 파일은 설치된 앱이 아닙니다.

프론트엔드만 핫 리로드로 실행:

```bash
npm --prefix web run dev
```

Mac 연결 없이 UI를 확인하려면 Vite URL 뒤에 `/?preview=browser`를 붙여 열거나(기본값: `http://localhost:5173/?preview=browser`), 페이지 상단의 **리모컨 미리보기**를 클릭하세요. `npm --prefix web run dev:preview`로 Vite를 시작하고 미리보기를 자동으로 열 수도 있습니다. 백엔드나 페어링이 필요하지 않으며, 시리즈 영상, 단일 영상, 첫 번째·마지막 에피소드, IINA, 일반 리모컨, 일시 정지, 잠금 상태를 전환할 수 있습니다. 버튼 조작은 Mac에 전송되지 않습니다. 상단 연결 상태에서 네 가지 언어도 확인할 수 있습니다. 이 미리보기는 Vite 개발 모드에서만 제공됩니다.

휴대폰 번역은 `web/src/i18n.ts`, Mac 번역은 `mac/Sources/GimmeRemote/Localization.swift`에 있습니다. 두 카탈로그 모두 번역 누락과 자리표시자 일치 여부를 검사합니다. 네이티브 패널 검사는 네 가지 언어에서 페어링 펼치기·접기, 권한 안내, 높이 제한 시 스크롤을 확인합니다. `mac/Resources/*.lproj/InfoPlist.strings`의 시스템 권한 설명은 시스템에 설정된 앱 언어를 따르며, 릴리스 스크립트가 복사합니다. 번역은 앱과 웹 번들에 포함되므로 추가 리소스를 다운로드할 필요가 없습니다.

`TransportChecks`는 HTTP / WebSocket 회귀 테스트를 실행한 뒤 종료됩니다. 포트 `19371`은 테스트 중에만 사용되며, 프론트엔드용 상시 백엔드가 아닙니다.

앱의 기본 포트는 `9271`입니다. Vite는 `/ws`를 `127.0.0.1:9271`로 프록시합니다. 개발 중 네이티브 앱을 실행할 때 다음 환경 변수를 설정하세요:

```text
GIMME_WEB_ROOT=/absolute/path/to/gimme-remote/web/dist
GIMME_DEV_ORIGINS=http://localhost:5173,http://192.168.1.2:5173
```

두 번째 Origin은 Vite를 실행하는 Mac의 실제 LAN IP 주소로 바꾸세요. 개발용 Origin은 허용 목록에 명시적으로 추가해야 합니다. 휴대폰에서 Vite에 접속할 때도 Mac의 IP 주소를 사용합니다. `VITE_REMOTE_URL=http://mac.local:9271`로 네이티브 서비스에 직접 연결할 수도 있지만, 이 경우에도 Vite 페이지의 Origin을 허용 목록에 추가해야 합니다.

릴리스 빌드는 `web/dist`를 `GimmeRemote.app/Contents/Resources/Web`으로 복사합니다. 페이지와 WebSocket은 같은 Origin을 사용하며, 운영 환경에서는 Node가 필요하지 않습니다. 네트워크가 바뀌면 메뉴 막대의 연결 주소도 갱신됩니다. 새 로컬 IP 주소의 페이지는 다시 페어링해야 할 수 있으므로, 안정적인 `.local` 주소를 저장하는 것을 권장합니다.

## CLI

```bash
gimme status   # 서비스, 권한, 연결 수, 접속 URL 표시
gimme pair     # 일회용 페어링 코드를 갱신하고 접속 URL 표시
gimme stop     # 원격 입력 일시 정지
gimme resume   # 원격 입력 재개
gimme player   # 브라우저 에피소드 버튼 감지 결과 확인
gimme --version
```

CLI는 현재 사용자 전용 디렉터리의 Unix 소켓으로 통신합니다. 메뉴 막대에서 입력 일시 정지, 기기 연결 해제, 모든 페어링 해제, 로그인 시 실행, 연결 중 디스플레이 잠자기 방지를 설정할 수 있습니다. 일시 정지해도 휴대폰 연결은 유지되며, 재개하면 다시 조작할 수 있습니다. 기기 연결을 해제해도 페어링은 저장되지만, 휴대폰에서 **다시 연결**을 눌러야 합니다. 페어링을 해제하면 다시 페어링해야 합니다.

## 릴리스

풀 리퀘스트는 검사를 실행합니다. 풀 리퀘스트 반영을 포함한 `master` push는 검사를 통과하면 `testing` 프리릴리스를 게시합니다. `vMAJOR.MINOR.PATCH` 형식의 태그는 정식 릴리스를 게시하고 Homebrew tap을 갱신합니다. 프리릴리스 접미사가 있는 태그는 프리릴리스를 게시하지만 정식 Cask는 갱신하지 않습니다.

빌드에는 Apple Developer 멤버십이 필요하지 않습니다. 필수로 설정할 사용자 지정 저장소 시크릿은 `lucientong/gimme-remote`의 `HOMEBREW_TAP_TOKEN` 하나뿐입니다. GitHub fine-grained PAT를 사용하여 **`lucientong/homebrew-tap`에만 Contents: Read and write** 권한을 부여하세요. 릴리스 게시용 토큰은 GitHub가 자동으로 제공합니다.

릴리스는 기본적으로 ad-hoc 서명되므로, 업데이트 후 macOS가 손쉬운 사용 권한을 해제할 수 있습니다. 권한을 유지하려면 자체 서명 코드 서명 인증서를 사용하고 선택적 시크릿 두 개를 설정하세요: `MACOS_SIGNING_P12_BASE64`(`.p12`의 base64)와 `MACOS_SIGNING_P12_PASSWORD`. Apple 계정은 필요 없지만, 릴리스마다 같은 인증서를 사용해야 합니다. 개인 키를 저장소에 저장하지 마세요.

macOS에서 로컬 릴리스 빌드:

```bash
bash scripts/build-release.sh
```

기본적으로 `build/` 아래에 Universal `GimmeRemote.app`, ZIP, `SHA256SUMS`를 생성합니다. 다시 빌드할 때는 `GIMME_OUTPUT_DIR`로 새 출력 디렉터리를 지정하세요. 기존 앱은 덮어쓰지 않습니다. `GIMME_SIGNING_IDENTITY`와 필요한 경우 `GIMME_SIGNING_KEYCHAIN`을 설정하면 ad-hoc 대신 고정된 서명 ID를 사용할 수 있습니다. `--unsigned`는 번들 구조 검증 전용이며 배포용 ZIP을 생성하지 않습니다.

## 프로젝트 구조

```text
mac/        Swift 네이티브 앱, 서버, 입력 처리, CLI, 핵심 테스트
web/        Preact / TypeScript / Vite 휴대폰 인터페이스
shared/     프로토콜 JSON Schema
scripts/    빌드, 핵심 검사, Homebrew Cask 생성
```

브라우저, iPhone, HDMI 디스플레이, 시스템 권한의 실제 동작은 실제 기기에서 확인해야 합니다. 자동 테스트가 모든 플레이어 상황을 검증하는 것은 아닙니다.

아이콘은 `swift scripts/make-icons.swift`로 `mac/AppIcon.icns`와 `web/public/icons/`에 생성합니다. 변경한 뒤에는 다시 생성하고 결과물을 커밋하세요.

이름은 영어 구어 표현인 *gimme the remote*(리모컨 좀 줘)에서 따왔습니다.
