import UIKit

extension KeyboardViewController {
    var allowsWordHelp: Bool {
        guard !privateField, textDocumentProxy.autocorrectionType != .no else { return false }
        switch observedKeyboardType {
        case .emailAddress, .URL, .numberPad, .decimalPad, .asciiCapableNumberPad, .twitter: return false
        default: return true
        }
    }

    func words(for word: String) -> (correction: String?, suggestions: [String]) {
        guard allowsWordHelp, !word.isEmpty, word.count <= 45, word.last?.isLetter == true,
              (textDocumentProxy.selectedText ?? "").isEmpty else { return (nil, []) }
        let range = NSRange(word.startIndex..., in: word)
        let miss = checker.rangeOfMisspelledWord(in: word, range: range, startingAt: 0, wrap: false, language: "en_US")
        let guesses = miss.location == 0 && miss.length == range.length
            ? checker.guesses(forWordRange: miss, in: word, language: "en_US") ?? [] : []
        let completions = checker.completions(forPartialWordRange: range, in: word, language: "en_US") ?? []
        let shortcuts = supplementaryWords[word.lowercased()] ?? []
        var suggestions = [word]
        for item in shortcuts.prefix(2) + guesses.prefix(2) + completions.prefix(3) where !suggestions.contains(item) {
            suggestions.append(item)
        }
        return (guesses.first, Array(suggestions.prefix(3)))
    }

    func updateCapitalization() {
        guard shift != .locked else { return }
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        switch textDocumentProxy.autocapitalizationType ?? .sentences {
        case .none: shift = .off
        case .allCharacters: shift = .once
        case .words: shift = before.last?.isWhitespace != false ? .once : .off
        default:
            let endsSentence = before.last?.isWhitespace == true &&
                before.trimmingCharacters(in: .whitespacesAndNewlines).last.map { ".!?".contains($0) } == true
            shift = before.isEmpty || before.last == "\n" || endsSentence ? .once : .off
        }
    }

    func updateLetterKeys() {
        for (name, key) in letterKeys {
            let title = shift == .off ? name : name.uppercased()
            key.setTitle(title, for: .normal)
            key.accessibilityLabel = title
        }
        let symbol = shift == .locked ? "capslock.fill" : (shift == .once ? "shift.fill" : "shift")
        shiftButton?.setImage(UIImage(systemName: symbol), for: .normal)
    }

    func refreshTyping() {
        let suggestions: [String]
        if let word = activeComposition, word.last?.isLetter == true {
            suggestions = words(for: word).suggestions
        } else {
            suggestions = nextWords()
        }
        for (index, key) in suggestionButtons.enumerated() {
            let value = index < suggestions.count ? suggestions[index] : ""
            key.setTitle(value, for: .normal)
            key.accessibilityLabel = value
            key.isEnabled = !value.isEmpty
            key.isAccessibilityElement = !value.isEmpty
        }
        updateLetterKeys()
    }

    func type(_ value: String) {
        typingFeedback?.removeFromSuperview()
        let proxy = textDocumentProxy
        let document = proxy.documentIdentifier
        if authoredDocument != document || !matchesAuthoredSuffix || !(proxy.selectedText ?? "").isEmpty { authored = "" }
        authoredDocument = document
        // Track only this keyboard’s current English word for suggestions.
        if allowsWordHelp, value.count == 1, value.first?.isLetter == true,
           (proxy.selectedText ?? "").isEmpty {
            let prior = activeComposition
            let word = prior.flatMap { $0.allSatisfy({ $0.isLetter }) ? $0 : nil } ?? ""
            if word.isEmpty { commitComposition() }
            mark(word + value)
        } else {
            commitComposition()
            proxy.insertText(value)
        }
        if !privateField && hasFullAccess && (value != "\n") {
            authored += value
            if authored.count >= 512 { finishObservation() }
        }
        if value == " " && authored.trimmingCharacters(in: .whitespaces).last.map({ ".!?".contains($0) }) == true {
            finishObservation()
        }
        updateCapitalization()
        refreshTyping()
    }

    func finishObservation() {
        defer { authored = ""; authoredDocument = nil }
        guard !privateField, hasFullAccess, !authored.isEmpty else { return }
        // Only text from this keyboard's literal typing path enters the local daily counters.
        let sample = authored
        do {
            guard try store.observationEnabled() else { return }
            try store.observe(sample)
            LocalReflectionAgent.shared.submit(sample, store: store)
        } catch {
            // Loss of shared storage must never block or erase an edit in the host app.
        }
    }

    func erase() {
        let proxy = textDocumentProxy
        if let current = activeComposition, let spelling = originalSpelling, current.hasSuffix(" ") {
            mark(spelling)
            suppressedWord = spelling
            if authored.hasSuffix(current) {
                authored = String(authored.dropLast(current.count)) + spelling
            }
        } else {
            let editing = activeComposition
            commitComposition()
            if !matchesAuthoredSuffix || !(proxy.selectedText ?? "").isEmpty { authored = "" }
            else if !authored.isEmpty { authored.removeLast() }
            proxy.deleteBackward()
            if let editing, editing.count > 1, editing.allSatisfy({ $0.isLetter }) {
                composition = (String(editing.dropLast()), proxy.documentIdentifier)
            }
        }
        updateCapitalization()
        refreshTyping()
    }

    func space() {
        if layout == .numbers || layout == .symbols {
            type(" ")
            layout = .letters
            showKeys()
            return
        }
        let now = Date()
        defer { lastSpace = now }
        let current = activeComposition
        if allowsWordHelp, current?.hasSuffix(" ") == true, now.timeIntervalSince(lastSpace) < 0.38,
           let marked = current, marked.dropLast().last?.isLetter == true {
            let ending = String(marked.dropLast()) + ". "
            mark(ending)
            commitComposition()
            if authored.hasSuffix(marked) { authored = String(authored.dropLast(marked.count)) + ending }
            finishObservation()
        } else if allowsWordHelp, let word = current, !word.isEmpty, word.allSatisfy({ $0.isLetter }) {
            var result = word
            if word != suppressedWord, let expansion = supplementaryWords[word.lowercased()]?.first, expansion != word {
                result = expansion
            } else if word == "i", word != suppressedWord {
                result = "I"
            } else if word != suppressedWord, word.count >= 2,
                      (word == word.lowercased() || word == word.capitalized),
                      let candidate = words(for: word.lowercased()).correction,
                      candidate.lowercased().distanceAtMostOne(from: word.lowercased()) {
                result = word.first?.isUppercase == true ? candidate.capitalized : candidate
            }
            mark(result + " ")
            originalSpelling = result == word ? nil : word
            if authored.hasSuffix(word) { authored = String(authored.dropLast(word.count)) + result + " " }
            suppressedWord = nil
        } else {
            type(" ")
        }
        updateCapitalization()
        refreshTyping()
    }

    // Instant English predictions between words. All lookups stay in the keyboard process.
    private func nextWords() -> [String] {
        guard allowsWordHelp, (textDocumentProxy.selectedText ?? "").isEmpty else { return [] }
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let trimmed = before.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || before.last == "\n" || trimmed.last.map({ ".!?".contains($0) }) == true {
            return ["I", "The", "I’m"]
        }
        guard before.last?.isWhitespace == true else { return [] }
        let prior = trimmed.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "'" }).last
        switch prior {
        case "i": return ["think", "am", "will"]
        case "we": return ["can", "are", "should"]
        case "you": return ["can", "are", "have"]
        case "thank": return ["you", "them", "everyone"]
        case "thanks": return ["for", "again", "so"]
        case "can", "could", "would": return ["you", "we", "I"]
        case "to": return ["the", "be", "get"]
        case "let": return ["me", "us", "them"]
        case "see": return ["you", "the", "if"]
        case "on": return ["the", "my", "your"]
        default: return ["the", "to", "and"]
        }
    }

    func acceptSuggestion(_ suggestion: String) {
        guard allowsWordHelp else { return }
        guard let word = activeComposition, word.last?.isLetter == true else {
            guard nextWords().contains(suggestion) else { return }
            type(suggestion + " ")
            return
        }
        guard words(for: word).suggestions.contains(suggestion) else { return }
        mark(suggestion + " ")
        originalSpelling = suggestion == word ? nil : word
        if authored.hasSuffix(word) { authored = String(authored.dropLast(word.count)) + suggestion + " " }
        updateCapitalization()
        refreshTyping()
    }

    var activeComposition: String? {
        guard let composition, composition.document == textDocumentProxy.documentIdentifier,
              (textDocumentProxy.selectedText ?? "").isEmpty,
              textDocumentProxy.documentContextBeforeInput?.hasSuffix(composition.text) == true else { return nil }
        return composition.text
    }

    func mark(_ text: String) {
        // Some host editors append each marked-text update. Submit literal key presses
        // exactly once and change only the differing suffix for a verified short word.
        let old = activeComposition ?? ""
        let common = zip(old, text).prefix(while: { $0.0 == $0.1 }).count
        let removing = old.dropFirst(common)
        guard removing.count <= 45, removing.allSatisfy({ $0.isASCII }) else { return }
        for _ in removing { textDocumentProxy.deleteBackward() }
        let addition = String(text.dropFirst(common))
        if !addition.isEmpty { textDocumentProxy.insertText(addition) }
        composition = (text, textDocumentProxy.documentIdentifier)
        originalSpelling = nil
    }

    func commitComposition() {
        composition = nil
        originalSpelling = nil
    }

}

private extension String {
    func distanceAtMostOne(from other: String) -> Bool {
        let left = Array(self), right = Array(other)
        if abs(left.count - right.count) > 1 { return false }
        if left.count == right.count {
            let different = left.indices.filter { left[$0] != right[$0] }
            if different.count <= 1 { return true }
            guard different.count == 2, different[1] == different[0] + 1 else { return false }
            return left[different[0]] == right[different[1]] && left[different[1]] == right[different[0]]
        }
        var a = 0, b = 0, differences = 0
        while a < left.count && b < right.count {
            if left[a] == right[b] { a += 1; b += 1; continue }
            differences += 1
            if differences > 1 { return false }
            if left.count >= right.count { a += 1 }
            if right.count >= left.count { b += 1 }
        }
        return differences + left.count - a + right.count - b <= 1
    }
}
