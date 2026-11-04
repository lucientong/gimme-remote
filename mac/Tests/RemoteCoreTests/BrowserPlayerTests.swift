import Foundation
import CoreGraphics
import Testing
@testable import RemoteCore

private func playerFixture(previous: Bool? = nil, next: Bool? = nil) -> [PlayerNode] {
    func button(_ name: String, x: Double, enabled: Bool = true) -> PlayerNode {
        .init(parent: 1, role: "AXButton", labels: [name],
              frame: CGRect(x: x, y: 500, width: 36, height: 24), enabled: enabled, pressable: true)
    }
    var nodes = [PlayerNode(parent: nil, role: "AXWebArea"), PlayerNode(parent: 0),
                 button("播放/暂停", x: 100), button("全屏", x: 700)]
    if let previous { nodes.append(button("上一个", x: 64, enabled: previous)) }
    if let next { nodes.append(button("下一个", x: 136, enabled: next)) }
    return nodes
}

@Test func playerControlsFollowPresenceAndBoundaryState() {
    #expect(BrowserPlayerDetection.select(playerFixture()) == nil)
    let first = playerFixture(previous: false, next: true)
    #expect(BrowserPlayerDetection.select(first)?.controls(in: first) == EpisodeControls(previous: false, next: true))
    let last = playerFixture(previous: true, next: false)
    #expect(BrowserPlayerDetection.select(last)?.controls(in: last) == EpisodeControls(previous: true, next: false))
    let nextOnly = playerFixture(next: true)
    #expect(BrowserPlayerDetection.select(nextOnly)?.controls(in: nextOnly) == EpisodeControls(next: true))
}

@Test func unrelatedAndAmbiguousControlsAreNotEpisodes() {
    var nodes = playerFixture(next: true)
    nodes[4].parent = 0
    #expect(BrowserPlayerDetection.select(nodes) == nil)
    nodes = playerFixture(next: true)
    nodes[4].visible = false
    #expect(BrowserPlayerDetection.select(nodes) == nil)
    nodes = playerFixture(next: true)
    nodes[4].labels = ["Seek forward"]
    #expect(BrowserPlayerDetection.select(nodes) == nil)
    nodes = playerFixture(next: true)
    nodes.append(nodes[4])
    #expect(BrowserPlayerDetection.select(nodes) == nil)
}

@Test func oldStateDoesNotAdvertiseEpisodeSupport() throws {
    let json = #"{"appName":"Chrome","bundleId":"com.google.Chrome","layout":"browser","locked":false,"accessibility":true,"paused":false,"captureAvailable":false}"#
    #expect(try JSONDecoder().decode(RemoteState.self, from: Data(json.utf8)).episodeControls == nil)
}

@Test func flattenedBrowserTreeRequiresMediaControlsInTheSameRow() {
    var nodes = playerFixture(next: true)
    nodes.append(.init(parent: 0, role: "AXButton", labels: ["音量"],
                       frame: CGRect(x: 500, y: 500, width: 36, height: 24), pressable: true))
    for index in 2..<nodes.count { nodes[index].parent = 0 }
    #expect(BrowserPlayerDetection.select(nodes)?.controls(in: nodes) == EpisodeControls(next: true))
    nodes[5].frame.origin.y = 1000
    #expect(BrowserPlayerDetection.select(nodes) == nil)
}

@Test func nestedBrowserControlsContinueToThePlayerContainer() {
    var nodes = playerFixture(previous: false, next: true)
    // Inner group contains play/fullscreen; episode buttons are sibling controls.
    nodes.append(.init(parent: 1))
    nodes[2].parent = 6
    nodes[3].parent = 6
    #expect(BrowserPlayerDetection.select(nodes)?.controls(in: nodes) == EpisodeControls(previous: false, next: true))
    // A nearby page-level Next still needs the flattened-tree media evidence.
    nodes[4].parent = 0
    nodes[5].parent = 0
    #expect(BrowserPlayerDetection.select(nodes) == nil)
}
