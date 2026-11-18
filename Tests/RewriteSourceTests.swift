import XCTest
@testable import Ownphrase

final class RewriteSourceTests: XCTestCase {
    func testSelectedTextRequiresSameDocumentSelectionAndAnchors() throws {
        let document = UUID()
        let source = try XCTUnwrap(RewriteSource(document: document, selection: "I’m here 🧑🏽‍💻", before: "One ", after: " end"))
        XCTAssertTrue(source.canReplace(document: document, selection: source.text, before: "One ", after: " end"))
        XCTAssertFalse(source.canReplace(document: UUID(), selection: source.text, before: "One ", after: " end"))
        XCTAssertFalse(source.canReplace(document: document, selection: nil, before: "One ", after: " end"))
        XCTAssertFalse(source.canReplace(document: document, selection: source.text, before: "Two ", after: " end"))
        XCTAssertFalse(source.canReplace(document: document, selection: source.text, before: "One ", after: " edited"))
    }

    func testVisiblePassageCanBeAppliedOnlyAfterExplicitSelection() throws {
        let document = UUID()
        let source = try XCTUnwrap(RewriteSource(document: document, selection: nil, before: "First line\nhello", after: " next"))
        XCTAssertEqual(source.text, "hello")
        XCTAssertFalse(source.canReplace(document: document, selection: nil, before: "First line\nhello", after: " next"))
        XCTAssertTrue(source.canReplace(document: document, selection: "hello", before: "More context. First line\n", after: " next"))
        XCTAssertFalse(source.canReplace(document: document, selection: "hello", before: "Moved elsewhere\n", after: " next"))
    }

    func testShortImplicitFragmentsNeedSelectionAndDocumentEdgesCanBeEmpty() throws {
        let doc = UUID()
        let partial = try XCTUnwrap(RewriteSource(document: doc, selection: nil, before: "P", after: nil))
        XCTAssertTrue(partial.needsSelection)
        let selected = try XCTUnwrap(RewriteSource(document: doc, selection: "P", before: nil, after: ""))
        XCTAssertFalse(selected.needsSelection)
        XCTAssertTrue(selected.canReplace(document: doc, selection: "P", before: "", after: nil))
        XCTAssertFalse(selected.canReplace(document: doc, selection: "P", before: "other", after: nil))
    }

    func testEmptyOrOversizePassagesRequireAnExplicitSmallerSelection() {
        for draft in ["", "  ", "old paragraph\n", String(repeating: "a", count: 4001)] {
            XCTAssertNil(RewriteSource(document: UUID(), selection: nil, before: draft, after: nil))
        }
    }
}
