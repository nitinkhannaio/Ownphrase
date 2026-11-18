import UIKit
import SwiftUI

private extension RewriteSource {
    @MainActor
    init?(proxy: UITextDocumentProxy) {
        self.init(document: proxy.documentIdentifier, selection: proxy.selectedText,
                  before: proxy.documentContextBeforeInput, after: proxy.documentContextAfterInput)
    }

    @MainActor
    func canReplace(_ proxy: UITextDocumentProxy) -> Bool {
        canReplace(document: proxy.documentIdentifier, selection: proxy.selectedText,
                   before: proxy.documentContextBeforeInput, after: proxy.documentContextAfterInput)
    }
}

extension KeyboardViewController {
    func resetReview() {
        request?.cancel()
        request = nil
        review = nil
        options = []
        optionIndex = 0
        lastMessage = nil
    }

    func makeMagicControl() -> UIView {
        // Resolve at tap time. A user can replace or remove the key while the
        // host keeps its keyboard process and first responder alive.
        let link = SetupLink(action: { [weak self] in self?.beginRewrite() ?? .discarded }) {
            Image(systemName: "wand.and.stars").font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle()).accessibilityLabel("Rewrite")
        }
        return UIHostingConfiguration { link }.margins(.all, 0).makeContentView()
    }

    func requestKeySetup() {
        guard !privateField else { return }
        UserDefaults(suiteName: "group.io.nitinkhanna.ownphrase")?.set(true, forKey: "pendingKeySetup")
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("io.nitinkhanna.ownphrase.setup" as CFString), nil, nil, true)
        // Give the URL tap time to leave this host before displaying its fallback.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.viewIfLoaded?.window != nil else { return }
            self.presentPanel(.setup("Add your API key in Ownphrase. If the app doesn’t open here, open it from your Home Screen."))
        }
    }

    func beginRewrite() -> OpenURLAction.Result {
        commitComposition()
        finishObservation()
        resetReview()
        guard !privateField else { presentPanel(.notice("Private field", "Return to typing to continue in this field.")); return .handled }
        guard hasFullAccess else {
            presentPanel(.notice("Allow Full Access", "In iPhone Settings, open Apps → Ownphrase → Keyboards and turn on Allow Full Access. This lets you send a rewrite to OpenAI."))
            return .systemAction(URL(string: "ownphrase://setup/keyboard")!)
        }
        do {
            guard try APIKeyStore.load() != nil else { requestKeySetup(); return .systemAction }
        } catch {
            presentPanel(.notice("Key unavailable", "Unlock your iPhone and try again. Your draft is still here."))
            return .handled
        }
        guard let source = RewriteSource(proxy: textDocumentProxy) else {
            let selection = textDocumentProxy.selectedText ?? ""
            let passage = selection.isEmpty ? (textDocumentProxy.documentContextBeforeInput ?? "").components(separatedBy: "\n").last ?? "" : selection
            if passage.count > RewriteSource.maximumCharacters { presentPanel(.notice("Choose a shorter passage", "Select up to 4,000 characters, then tap Rewrite.")) }
            else { presentPanel(.notice("Write something first", "Type a sentence or select text in your message, then tap Rewrite.")) }
            return .handled
        }
        review = source
        showReview()
        return .handled
    }

    func endReview() {
        resetReview()
        configureField()
        showKeys()
    }

    func presentPanel(_ page: PanelPage) {
        panelActive = true
        if case .tones = page { previewingSource = true } else { previewingSource = false }
        clearContent()
        let panel = RewritePanel(page: page, close: { [weak self] in self?.endReview() },
            choose: { [weak self] in self?.generate($0) },
            change: { [weak self] in self?.showReview() },
            move: { [weak self] index in self?.optionIndex = index; self?.lastMessage = nil; self?.showOptions() },
            use: { [weak self] in self?.apply() }, copy: { [weak self] in self?.copyOption() },
            openSetup: { [weak self] in self?.requestKeySetup() })
        let host = UIHostingController(rootView: panel)
        addChild(host)
        host.view.backgroundColor = .clear
        content.addArrangedSubview(host.view)
        host.didMove(toParent: self)
        panelHost = host
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }

    func showReview() {
        guard let source = review else { endReview(); return }
        options = []
        presentPanel(.tones(source.text, source.selected, lastMessage))
    }

    func generate(_ tone: RewriteTone) {
        guard let source = review, request == nil else { return }
        guard hasFullAccess, !privateField, source.document == textDocumentProxy.documentIdentifier else { endReview(); return }
        guard refreshPreviewIfChanged() == false else { return }
        lastMessage = nil
        presentPanel(.working(tone))
        request = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await OpenAIClient.rewrite(text: source.text, instruction: tone.prompt, profile: store.profile())
                try Task.checkCancellation()
                guard hasFullAccess, !privateField, source.document == textDocumentProxy.documentIdentifier else {
                    endReview()
                    return
                }
                guard !result.isEmpty else { throw ModelRequestError.invalidResponse }
                options = result
                optionIndex = 0
                request = nil
                showOptions()
            } catch {
                guard !Task.isCancelled else { return }
                request = nil
                if case ModelRequestError.invalidKey = error {
                    presentPanel(.setup("OpenAI rejected this key. Open Ownphrase to replace it."))
                } else if case ModelRequestError.missingKey = error {
                    presentPanel(.setup("Open Ownphrase to add your API key."))
                } else {
                    lastMessage = error.localizedDescription
                    showReview()
                }
            }
        }
    }

    @discardableResult
    func refreshPreviewIfChanged() -> Bool {
        guard previewingSource, let previous = review else { return false }
        guard let current = RewriteSource(proxy: textDocumentProxy), current.document == previous.document else {
            endReview()
            return true
        }
        guard previous.text != current.text || previous.selected != current.selected else { return false }
        review = current
        lastMessage = nil
        showReview()
        return true
    }

    func refreshReplacementState() {
        guard panelActive, let source = review else { return }
        if privateField || source.document != textDocumentProxy.documentIdentifier { endReview(); return }
        if previewingSource { refreshPreviewIfChanged(); return }
        guard !options.isEmpty else { return }
        if selectionWasValid != source.canReplace(textDocumentProxy) { showOptions() }
    }

    func showOptions() {
        guard let source = review, options.indices.contains(optionIndex) else { return }
        selectionWasValid = source.canReplace(textDocumentProxy)
        presentPanel(.result(options[optionIndex].text, optionIndex, options.count, selectionWasValid, lastMessage))
    }

    func copyOption() {
        guard !privateField, hasFullAccess, review?.document == textDocumentProxy.documentIdentifier,
              options.indices.contains(optionIndex) else { endReview(); return }
        UIPasteboard.general.setItems([["public.utf8-plain-text": options[optionIndex].text]], options: [.localOnly: true])
        endReview()
        let feedback = UILabel()
        feedback.text = "Copied. Paste in your message."
        feedback.font = .preferredFont(forTextStyle: .subheadline)
        feedback.textColor = .label
        feedback.textAlignment = .center
        feedback.backgroundColor = .secondarySystemGroupedBackground
        feedback.layer.cornerRadius = 8
        feedback.clipsToBounds = true
        feedback.translatesAutoresizingMaskIntoConstraints = false
        feedback.isUserInteractionEnabled = false
        let lastSuggestion = suggestionButtons.last
        toolbar.addSubview(feedback)
        NSLayoutConstraint.activate([
            feedback.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 6),
            feedback.trailingAnchor.constraint(equalTo: lastSuggestion?.trailingAnchor ?? toolbar.trailingAnchor),
            feedback.topAnchor.constraint(equalTo: toolbar.topAnchor, constant: 2),
            feedback.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: -2)
        ])
        typingFeedback = feedback
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak feedback] in feedback?.removeFromSuperview() }
        UIAccessibility.post(notification: .announcement, argument: feedback.text)
    }

    func apply() {
        guard hasFullAccess, !privateField, let source = review, source.document == textDocumentProxy.documentIdentifier,
              options.indices.contains(optionIndex) else { endReview(); return }
        guard source.canReplace(textDocumentProxy) else { showOptions(); return }
        let option = options[optionIndex]
        options = []
        textDocumentProxy.insertText(option.text)
        do {
            try store.record(original: source.text, accepted: option)
            endReview()
        } catch {
            resetReview()
            presentPanel(.notice("Rewrite inserted", "Ownphrase couldn’t save this example to your notebook."))
        }
    }
}
