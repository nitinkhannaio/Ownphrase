import UIKit

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
        instruction = nil
        rewriteInstruction = ""
        options = []
        lastMessage = nil
    }

    func beginRewrite() {
        commitComposition()
        finishObservation()
        resetReview()
        if privateField { showNotice("Rewriting is unavailable in this field."); return }
        guard hasFullAccess else { showNotice("Enable Allow Full Access in iPhone keyboard settings to use OpenAI rewrites."); return }
        guard let source = RewriteSource(proxy: textDocumentProxy) else {
            showNotice("Select a passage of up to 4,000 characters in your message, then tap Rewrite.")
            return
        }
        review = source
        showReview()
    }

    func endReview() {
        resetReview()
        configureField()
        showKeys()
    }

    func showNotice(_ message: String) {
        clearContent()
        content.addArrangedSubview(panelHeader("Rewrite"))
        content.addArrangedSubview(scrollArea([bodyLabel(message)]))
    }

    func panelHeader(_ title: String) -> UIStackView {
        let row = UIStackView()
        row.alignment = .center
        row.spacing = 6
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 2)
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .headline)
        label.text = title
        row.addArrangedSubview(label)
        let back = button("Back to typing", symbol: "keyboard", special: true) { [weak self] in self?.endReview() }
        back.widthAnchor.constraint(equalToConstant: 44).isActive = true
        row.addArrangedSubview(back)
        row.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return row
    }

    func bodyLabel(_ text: String, secondary: Bool = false) -> UILabel {
        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: secondary ? .footnote : .body)
        label.textColor = secondary ? .secondaryLabel : .label
        return label
    }

    func scrollArea(_ views: [UIView]) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = true
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 2),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -6),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -16)
        ])
        return scroll
    }

    func showReview() {
        guard let source = review else { endReview(); return }
        if let instruction { rewriteInstruction = instruction; self.instruction = nil }
        clearContent()
        content.addArrangedSubview(panelHeader("Rewrite in my voice"))
        var items: [UIView] = [bodyLabel(source.selected ? "Selected passage" : "Text before the cursor", secondary: true), bodyLabel(source.text)]
        if !source.selected {
            items.append(bodyLabel("To apply a rewrite, select this exact passage in your message. You can also select it before tapping Rewrite.", secondary: true))
        }
        if let lastMessage { items.append(bodyLabel(lastMessage)) }
        let customize = button(rewriteInstruction.isEmpty ? "Add an instruction…" : rewriteInstruction, special: true) { [weak self] in
            guard let self else { return }
            instruction = rewriteInstruction
            layout = .letters
            shift = .off
            showKeys()
        }
        customize.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
        items.append(customize)
        content.addArrangedSubview(scrollArea(items))
        let generate = button("Generate rewrites") { [weak self] in self?.generate() }
        generate.heightAnchor.constraint(equalToConstant: 40).isActive = true
        content.addArrangedSubview(generate)
    }

    func generate() {
        guard let source = review, request == nil else { return }
        guard hasFullAccess, !privateField, source.document == textDocumentProxy.documentIdentifier else {
            showNotice("The field or its permissions changed. Return to typing and select the passage again.")
            return
        }
        clearContent()
        content.addArrangedSubview(panelHeader("Rewriting…"))
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.startAnimating()
        content.addArrangedSubview(spinner)
        let prompt = rewriteInstruction.isEmpty ? "Polish this passage in my voice. Preserve its meaning and facts." : rewriteInstruction
        request = Task { [weak self] in
            guard let self else { return }
            do {
                let profile = try store.profile()
                let result = try await OpenAIClient.rewrite(text: source.text, instruction: prompt, profile: profile)
                try Task.checkCancellation()
                guard !result.isEmpty else { throw KeyboardRewriteError.empty }
                options = result
                lastMessage = nil
                request = nil
                showOptions()
            } catch {
                guard !Task.isCancelled else { return }
                lastMessage = error.localizedDescription
                request = nil
                showReview()
            }
        }
    }

    func showOptions() {
        guard let source = review else { return }
        clearContent()
        content.addArrangedSubview(panelHeader("Choose a rewrite"))
        var items: [UIView] = []
        if let lastMessage { items.append(bodyLabel(lastMessage)) }
        if !source.canReplace(textDocumentProxy) {
            items.append(bodyLabel("Select the original passage in your message, then tap Use on the version you want.", secondary: true))
        }
        for (index, option) in options.enumerated() {
            items.append(bodyLabel(option.text))
            let use = button("Use version \(index + 1)") { [weak self] in self?.apply(option) }
            use.heightAnchor.constraint(equalToConstant: 36).isActive = true
            items.append(use)
        }
        let revise = button("Change instruction", special: true) { [weak self] in
            self?.lastMessage = nil
            self?.showReview()
        }
        revise.heightAnchor.constraint(equalToConstant: 36).isActive = true
        items.append(revise)
        content.addArrangedSubview(scrollArea(items))
    }

    func apply(_ option: RewriteOption) {
        guard let source = review, !privateField, source.canReplace(textDocumentProxy) else {
            lastMessage = "The original passage must still be selected in the same field. If you edited it, start a new rewrite."
            showOptions()
            return
        }
        // One native replacement avoids partial erasure in apps that return delayed proxy context.
        textDocumentProxy.insertText(option.text)
        do {
            try store.record(original: source.text, accepted: option)
            endReview()
        } catch {
            resetReview()
            showNotice("The rewrite was inserted. Ownphrase couldn’t save this example for learning.")
        }
    }
}

private enum KeyboardRewriteError: LocalizedError {
    case empty
    var errorDescription: String? { "No rewrite was returned. Try again." }
}
