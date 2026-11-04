import Foundation
import CoreGraphics

/// A small, platform-independent view of the current tab's accessibility tree.
public struct PlayerNode: Sendable {
    public var parent: Int?
    public var role: String
    public var labels: [String]
    public var frame: CGRect
    public var visible: Bool
    public var enabled: Bool
    public var pressable: Bool
    public init(parent: Int?, role: String = "AXGroup", labels: [String] = [], frame: CGRect = .zero,
                visible: Bool = true, enabled: Bool = true, pressable: Bool = false) {
        self.parent = parent; self.role = role; self.labels = labels; self.frame = frame
        self.visible = visible; self.enabled = enabled; self.pressable = pressable
    }
}

public enum BrowserPlayerDetection {
    public struct Selection: Sendable {
        public var previous: Int?
        public var next: Int?
        public func controls(in nodes: [PlayerNode]) -> EpisodeControls? {
            guard previous != nil || next != nil else { return nil }
            return .init(previous: previous.map { nodes[$0].enabled }, next: next.map { nodes[$0].enabled })
        }
    }

    private enum Kind { case play, previous, next, supporting }
    private static func kind(_ node: PlayerNode) -> Kind? {
        guard node.visible, node.pressable, node.role == "AXButton" else { return nil }
        for label in node.labels {
            // Accessible names often append a keyboard hint, e.g. "Next video (Shift+N)".
            let name = label.lowercased().components(separatedBy: "(")[0]
                .components(separatedBy: "（")[0].trimmingCharacters(in: .whitespacesAndNewlines)
            if ["play", "pause", "play/pause", "play / pause", "播放", "暂停", "播放/暂停", "播放 / 暂停",
                "再生", "一時停止", "再生/一時停止", "재생", "일시중지", "재생/일시중지"].contains(name) { return .play }
            if ["previous", "previous episode", "previous video", "previous track", "上一集", "上一话", "上一話",
                "上一个", "上一個", "上一个视频", "上一個視頻", "前の動画", "前のエピソード", "前へ",
                "이전", "이전 동영상", "이전 에피소드"].contains(name) { return .previous }
            if ["next", "next episode", "next video", "next track", "下一集", "下一话", "下一話",
                "下一个", "下一個", "下一个视频", "下一個視頻", "次の動画", "次のエピソード", "次へ",
                "다음", "다음 동영상", "다음 에피소드"].contains(name) { return .next }
            if ["fullscreen", "full screen", "exit fullscreen", "mute", "unmute", "volume", "全屏", "退出全屏",
                "静音", "取消静音", "音量", "フルスクリーン", "ミュート", "전체 화면", "음소거"].contains(name) { return .supporting }
        }
        return nil
    }

    /// Use the smallest local control group containing play/pause plus a media-specific control.
    /// Bare "Next" elsewhere on a page is pagination, not evidence of episode navigation.
    public static func select(_ nodes: [PlayerNode]) -> Selection? {
        let kinds = nodes.map(kind)
        let plays = nodes.indices.filter { kinds[$0] == .play && nodes[$0].enabled }
        guard plays.count == 1, let play = plays.first else { return nil }
        func inside(_ index: Int, _ ancestor: Int) -> Bool {
            var current: Int? = index
            for _ in 0..<64 {
                guard let value = current, nodes.indices.contains(value) else { return false }
                if value == ancestor { return true }
                current = nodes[value].parent
            }
            return false
        }
        func adjacent(_ index: Int, distance: CGFloat = 180) -> Bool {
            let a = nodes[play].frame, b = nodes[index].frame
            guard !a.isEmpty, !b.isEmpty else { return false }
            return abs(a.midY - b.midY) <= max(48, a.height * 2)
                && abs(a.midX - b.midX) <= max(distance, a.width * 4)
        }
        func selection(_ controls: [Int]) -> Selection? {
            let previous = controls.filter { kinds[$0] == .previous && adjacent($0) }
            let next = controls.filter { kinds[$0] == .next && adjacent($0) }
            guard previous.count <= 1, next.count <= 1, !previous.isEmpty || !next.isEmpty else { return nil }
            return .init(previous: previous.first, next: next.first)
        }
        var ancestor = nodes[play].parent
        for _ in 0..<64 {
            guard let group = ancestor, nodes.indices.contains(group) else { break }
            let controls = nodes.indices.filter { kinds[$0] != nil && inside($0, group) }
            if nodes[group].role == "AXWebArea" {
                // Browsers can flatten unnamed DIVs out of the AX tree. In that case require
                // two media-specific buttons in the same control row, as well as nearby episode buttons.
                let supporting = controls.filter { kinds[$0] == .supporting && adjacent($0, distance: 1200) }
                return supporting.count >= 2 ? selection(controls) : nil
            }
            if ["AXWindow", "AXApplication", "AXScrollArea"].contains(nodes[group].role) { break }
            // Chromium retains some nested control groups while flattening others.
            // Play/volume may share an inner group, with episode buttons in its parent.
            if controls.contains(where: { kinds[$0] == .supporting }),
               let match = selection(controls) { return match }
            ancestor = nodes[group].parent
        }
        return nil
    }
}
