import Foundation

enum InterfaceLanguage: String, CaseIterable, Sendable {
    case zh, en, ja, ko
    var name: String {
        switch self {
        case .zh: "中文"
        case .en: "English"
        case .ja: "日本語"
        case .ko: "한국어"
        }
    }
    static func resolve(_ preferred: [String]) -> Self {
        for tag in preferred {
            if let base = tag.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first,
               let language = Self(rawValue: String(base)) { return language }
        }
        return .en
    }
}

enum NativeText: CaseIterable, Sendable {
    case language, automatic, starting, needsPermission, paused, locked, waiting
    case connectedOne, connectedCount, pairedOne, pairedCount
    case vaultWarning, retryVault, close, quit, remote, resume, pause
    case permissionTitle, permissionSteps, grantPermission, permissionRetry
    case addDevice, scan, refreshCode, collapse, expiredCode, address, copyAddress
    case general, preventSleep, launchAtLogin, devices, revokeWarning, cancel, revoke
    case disconnect, revokeAll, attention, openMenu
    case serverFailure, cliFailure, codeFailure, revokeFailure, loginFailure
}

struct NativeNotice: Sendable {
    let key: NativeText
    var detail = ""
}

/// Code catalogs are bundled in the executable, including standalone SwiftPM builds.
struct NativeLocalization: Sendable {
    static let preferenceKey = "gimme.language"
    let language: InterfaceLanguage
    init(choice: String, preferred: [String] = Locale.preferredLanguages) {
        language = InterfaceLanguage(rawValue: choice) ?? InterfaceLanguage.resolve(preferred)
    }
    static func savedChoice(in defaults: UserDefaults = .standard) -> String {
        let choice = defaults.string(forKey: preferenceKey) ?? "auto"
        return InterfaceLanguage(rawValue: choice) != nil ? choice : "auto"
    }
    func text(_ key: NativeText, _ values: [String: String] = [:]) -> String {
        var text = Self.catalog[key]?[language] ?? Self.catalog[key]?[.en] ?? ""
        for (name, value) in values { text = text.replacingOccurrences(of: "{\(name)}", with: value) }
        return text
    }
    func connected(_ count: Int) -> String {
        text(count == 1 ? .connectedOne : .connectedCount, ["count": String(count)])
    }
    func paired(_ count: Int) -> String {
        text(count == 1 ? .pairedOne : .pairedCount, ["count": String(count)])
    }
    private static func row(_ zh: String, _ en: String, _ ja: String, _ ko: String) -> [InterfaceLanguage: String] {
        [.zh: zh, .en: en, .ja: ja, .ko: ko]
    }
    static let catalog: [NativeText: [InterfaceLanguage: String]] = [
        .language: row("语言", "Language", "言語", "언어"),
        .automatic: row("跟随系统", "System default", "システムに合わせる", "시스템 설정 따르기"),
        .starting: row("正在启动…", "Starting…", "起動中…", "시작 중…"),
        .needsPermission: row("需要授权", "Permission needed", "許可が必要", "권한 필요"),
        .paused: row("已暂停", "Paused", "一時停止中", "일시 정지됨"),
        .locked: row("Mac 已锁定", "Mac locked", "Mac はロック中", "Mac 잠김"),
        .waiting: row("等待手机连接", "Waiting for a phone", "端末の接続待ち", "휴대폰 연결 대기 중"),
        .connectedOne: row("{count} 台已连接", "{count} connected", "{count}台接続済み", "{count}대 연결됨"),
        .connectedCount: row("{count} 台已连接", "{count} connected", "{count}台接続済み", "{count}대 연결됨"),
        .pairedOne: row("{count} 台已配对", "{count} paired device", "{count}台ペアリング済み", "{count}대 페어링됨"),
        .pairedCount: row("{count} 台已配对", "{count} paired devices", "{count}台ペアリング済み", "{count}대 페어링됨"),
        .vaultWarning: row("无法读取钥匙串中的已配对设备，手机需要重新配对。可点“更新配对码”后重新扫码。",
                           "Paired devices could not be read from Keychain. Refresh the pairing code and scan again to pair your phone.",
                           "キーチェーンから端末を読み込めません。コードを更新し、再度スキャンしてペアリングしてください。",
                           "키체인에서 페어링된 기기를 읽을 수 없습니다. 코드를 갱신하고 다시 스캔하여 페어링하세요."),
        .retryVault: row("重新读取钥匙串", "Retry Keychain", "キーチェーンを再読込", "키체인 다시 읽기"),
        .close: row("关闭", "Dismiss", "閉じる", "닫기"),
        .quit: row("退出", "Quit", "終了", "종료"),
        .remote: row("遥控", "Remote", "リモート操作", "원격 조작"),
        .resume: row("恢复遥控", "Resume remote input", "リモート操作を再開", "원격 조작 재개"),
        .pause: row("暂停遥控", "Pause remote input", "リモート操作を一時停止", "원격 조작 일시 정지"),
        .permissionTitle: row("需要辅助功能权限，手机才能控制这台 Mac",
                              "Allow Accessibility so your phone can control this Mac",
                              "この Mac を操作するにはアクセシビリティの許可が必要です",
                              "휴대폰으로 Mac을 조작하려면 손쉬운 사용 권한이 필요합니다"),
        .permissionSteps: row("① 点下面的按钮打开系统设置\n② 打开 Gimme Remote 的开关",
                              "① Open System Settings below\n② Enable Gimme Remote",
                              "① 下のボタンでシステム設定を開く\n② Gimme Remote を有効にする",
                              "① 아래 버튼으로 시스템 설정 열기\n② Gimme Remote 켜기"),
        .grantPermission: row("授权辅助功能", "Allow Accessibility", "アクセシビリティを許可", "손쉬운 사용 허용"),
        .permissionRetry: row("已经打开仍无效：在列表中选中它点“−”删除，再重新添加。",
                              "Already enabled but not working? Select it in the list, remove it with “−”, then add it again.",
                              "有効でも動かない場合：一覧で選択し「−」で削除してから、再度追加してください。",
                              "이미 켜져 있는데 작동하지 않나요? 목록에서 선택 후 “−”로 삭제하고 다시 추가하세요."),
        .addDevice: row("添加新设备", "Add a device", "端末を追加", "기기 추가"),
        .scan: row("用手机相机扫码 · 2 分钟内有效", "Scan with your phone · Valid for 2 minutes",
                   "スマートフォンでスキャン · 2分間有効", "휴대폰 카메라로 스캔 · 2분간 유효"),
        .refreshCode: row("更新配对码", "Refresh pairing code", "コードを更新", "페어링 코드 갱신"),
        .collapse: row("收起", "Hide", "閉じる", "접기"),
        .expiredCode: row("配对码已失效，点“更新配对码”重新生成",
                          "Pairing code expired. Refresh it to generate a new one.",
                          "コードの有効期限が切れました。更新して再発行してください。",
                          "페어링 코드가 만료되었습니다. 갱신하여 새 코드를 받으세요."),
        .address: row("连接地址", "Connection address", "接続アドレス", "연결 주소"),
        .copyAddress: row("复制地址", "Copy address", "アドレスをコピー", "주소 복사"),
        .general: row("通用", "General", "一般", "일반"),
        .preventSleep: row("手机连接时，不让显示器休眠", "Keep display awake while a phone is connected",
                           "端末の接続中は画面のスリープを防ぐ", "휴대폰 연결 중 디스플레이 잠자기 방지"),
        .launchAtLogin: row("登录时启动", "Launch at login", "ログイン時に起動", "로그인 시 실행"),
        .devices: row("设备", "Devices", "端末", "기기"),
        .revokeWarning: row("所有手机都要重新配对", "All phones will need to pair again",
                            "すべての端末で再ペアリングが必要です", "모든 휴대폰을 다시 페어링해야 합니다"),
        .cancel: row("取消", "Cancel", "キャンセル", "취소"),
        .revoke: row("撤销全部", "Revoke all", "すべて解除", "모두 해제"),
        .disconnect: row("断开全部设备", "Disconnect all devices", "すべての端末を切断", "모든 기기 연결 해제"),
        .revokeAll: row("撤销全部配对…", "Revoke all pairings…", "すべてのペアリングを解除…", "모든 페어링 해제…"),
        .attention: row("需要处理", "Needs attention", "確認が必要", "확인 필요"),
        .openMenu: row("请从菜单栏打开 Gimme Remote", "Open Gimme Remote from the menu bar",
                       "メニューバーから Gimme Remote を開いてください", "메뉴 막대에서 Gimme Remote를 여세요"),
        .serverFailure: row("服务启动失败：{detail}", "Service failed to start: {detail}",
                            "サービスを起動できません：{detail}", "서비스를 시작하지 못했습니다: {detail}"),
        .cliFailure: row("CLI 服务不可用：{detail}", "CLI service unavailable: {detail}",
                         "CLI サービスを利用できません：{detail}", "CLI 서비스를 사용할 수 없습니다: {detail}"),
        .codeFailure: row("配对码生成失败", "Could not generate a pairing code",
                          "ペアリングコードを生成できません", "페어링 코드를 생성하지 못했습니다"),
        .revokeFailure: row("无法撤销设备：Keychain 写入失败", "Could not revoke devices: Keychain write failed",
                            "端末を解除できません：キーチェーンへの書き込み失敗", "기기를 해제하지 못했습니다: 키체인 쓰기 실패"),
        .loginFailure: row("登录启动设置失败：{detail}", "Could not set launch at login: {detail}",
                           "ログイン時の起動を設定できません：{detail}", "로그인 시 실행을 설정하지 못했습니다: {detail}"),
    ]
}
