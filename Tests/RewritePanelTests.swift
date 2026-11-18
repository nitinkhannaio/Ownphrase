import XCTest
import SwiftUI

@MainActor
final class RewritePanelTests: XCTestCase {
    func testEveryToneHasItsOwnInstruction() {
        XCTAssertEqual(RewriteTone.allCases.first, .myVoice)
        XCTAssertEqual(Set(RewriteTone.allCases.map(\.prompt)).count, RewriteTone.allCases.count)
        XCTAssertTrue(RewriteTone.allCases.contains(.professional))
    }

    func testCompactAndAccessiblePanels() throws {
        // Capture the production panel at the sizes supplied by the keyboard controller.
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let base = UIViewController()
        window.rootViewController = base
        window.isHidden = false
        defer { window.isHidden = true }
        let passage = "Can we move our call to tomorrow morning?"
        for (name, page, width, height, textSize) in [
            ("tones", PanelPage.tones(passage, true, nil), 402, 249, DynamicTypeSize.large),
            ("large-type", .tones(passage, false, nil), 375, 249, .accessibility3),
            ("large-error", .tones(String(repeating: passage, count: 85), false, "Connection lost. Try a tone again."), 375, 249, .accessibility3),
            ("dark-tones", .tones(passage, true, nil), 402, 249, .large),
            ("setup", .setup("Open Ownphrase to add your API key."), 402, 249, .large),
            ("notice", .notice("Write something first", "Type a sentence or select text in your message."), 402, 249, .large),
            ("short-pass", .tones("P", false, nil), 402, 249, .large),
            ("result", .result("Could we reschedule our call for tomorrow morning?", 0, 2, true, nil), 402, 249, .large),
            ("single-option", .result(passage, 0, 1, true, nil), 402, 249, .large),
            ("copy-result", .result(passage, 1, 2, false, nil), 402, 249, .large),
            ("landscape", .tones(passage, true, nil), 724, 181, .large),
            ("working", .working(.friendly), 402, 249, .large)
        ] {
            let panel = RewritePanel(page: page, close: {}, choose: { _ in }, change: {}, move: { _ in },
                                     use: {}, copy: {}, openSetup: {}).environment(\.dynamicTypeSize, textSize)
            let host = UIHostingController(rootView: panel)
            host.overrideUserInterfaceStyle = name == "dark-tones" ? .dark : .light
            base.addChild(host)
            host.view.frame = CGRect(x: 0, y: 100, width: width, height: height)
            host.view.backgroundColor = UIColor(white: name == "dark-tones" ? 23/255 : 0.9, alpha: 1)
            base.view.addSubview(host.view)
            host.didMove(toParent: base)
            host.view.layoutIfNeeded()
            let renderer = UIGraphicsImageRenderer(bounds: host.view.bounds)
            var rendered = false
            let image = renderer.image { _ in rendered = host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
            XCTAssertTrue(rendered, name)
            let capture = XCTAttachment(image: image)
            capture.name = name
            capture.lifetime = .keepAlways
            add(capture)
            host.willMove(toParent: nil)
            host.view.removeFromSuperview()
            host.removeFromParent()
        }
    }
}
