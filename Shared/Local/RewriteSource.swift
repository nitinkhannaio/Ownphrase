import Foundation

struct RewriteSource {
    static let maximumCharacters = 4_000
    let document: UUID
    let text: String
    let selected: Bool
    let before: String?
    let after: String?

    init?(document: UUID, selection: String?, before: String?, after: String?) {
        let selectedText = selection ?? ""
        selected = !selectedText.isEmpty
        // Hosts can supply truncated context. The preview always shows the exact model input.
        let visible = before ?? ""
        let paragraph = visible.split(separator: "\n", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        let candidate = selected ? selectedText : paragraph
        guard !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              candidate.count <= Self.maximumCharacters else { return nil }
        self.document = document
        self.before = before
        self.after = after
        text = candidate
    }

    func canReplace(document: UUID, selection: String?, before: String?, after: String?) -> Bool {
        guard document == self.document, selection?.utf8.elementsEqual(text.utf8) == true,
              after == self.after else { return false }
        if selected { return self.before == before }
        // A host may expose more leading context once the user selects a previously unselected span.
        let leadingAnchor = String((self.before ?? "").dropLast(text.count).suffix(16))
        return (before ?? "").hasSuffix(leadingAnchor)
    }
}
