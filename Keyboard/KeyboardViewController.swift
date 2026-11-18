import UIKit

/// All host text access stays on the keyboard's main thread. Network access is explicit.
final class KeyboardViewController: UIInputViewController {
    enum Layout { case letters, numbers, symbols, emoji, digits }
    enum Shift { case off, once, locked }
    let content = UIStackView()
    let toolbar = UIStackView()
    let checker = UITextChecker()
    var supplementaryWords: [String: [String]] = [:]
    let store = OwnStore()
    var layout: Layout = .letters
    var shift: Shift = .off
    var letterKeys: [(String, UIButton)] = []
    var shiftButton: UIButton?
    var suggestionButtons: [UIButton] = []
    var instruction: String?
    var request: Task<Void, Never>?
    var review: RewriteSource?
    var options: [RewriteOption] = []
    var rewriteInstruction = ""

    var keyHeight: NSLayoutConstraint?
    var areaTop: NSLayoutConstraint?
    var areaBottom: NSLayoutConstraint?
    weak var keyRows: UIStackView?
    var lastShift = Date.distantPast
    var lastSpace = Date.distantPast
    var repeatTimer: Timer?
    var panOrigin: CGFloat = 0
    var panOffset = 0
    var composition: (text: String, document: UUID)?
    var originalSpelling: String?
    var authored = ""
    var authoredDocument: UUID?
    var observedKeyboardType: UIKeyboardType?
    var lastMessage: String?
    var suppressedWord: String?


    var privateField: Bool {
        let proxy = textDocumentProxy
        return proxy.isSecureTextEntry == true || [.password, .newPassword, .oneTimeCode, .creditCardNumber, .username].contains(proxy.textContentType ?? nil)
    }

    override func loadView() {
        let surface = KeyboardSurface(frame: .zero, inputViewStyle: .default)
        surface.allowsSelfSizing = true
        view = surface
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        requestSupplementaryLexicon { [weak self] lexicon in
            self?.supplementaryWords = Dictionary(grouping: lexicon.entries, by: { $0.userInput.lowercased() })
                .mapValues { $0.map(\.documentText) }
        }
        content.axis = .vertical
        content.spacing = 6
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        let height = view.heightAnchor.constraint(equalToConstant: 260)
        height.priority = .defaultHigh
        keyHeight = height
        let top = content.topAnchor.constraint(equalTo: view.topAnchor, constant: 4)
        let bottom = content.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -3)
        areaTop = top
        areaBottom = bottom
        NSLayoutConstraint.activate([
            top, bottom,
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            height
        ])
        view.backgroundColor = .clear
        configureField()
        showKeys()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let wide = view.bounds.width > 560
        keyHeight?.constant = wide ? 187 : 260
        areaTop?.constant = wide ? 2 : 4
        areaBottom?.constant = wide ? -4 : -3
        keyRows?.spacing = wide ? 8 : 11
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        commitComposition()
        finishObservation()
        resetReview()
        stopRepeating()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        configureField()
        showKeys()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        if authoredDocument != textDocumentProxy.documentIdentifier ||
           (!authored.isEmpty && textDocumentProxy.documentContextBeforeInput?.isEmpty != false &&
            textDocumentProxy.documentContextAfterInput?.isEmpty != false &&
            (textDocumentProxy.selectedText ?? "").isEmpty) {
            // Message composers commonly clear the field on Send while leaving the keyboard open.
            finishObservation()
        } else if !matchesAuthoredSuffix {
            // A cursor move or host revision invalidates an unfinished sample.
            authored = ""
        }
        if let review {
            if review.document != textDocumentProxy.documentIdentifier { endReview() }
            return
        }
        if observedKeyboardType != textDocumentProxy.keyboardType {
            configureField()
            showKeys()
        } else {
            updateCapitalization()
            refreshTyping()
        }
    }

    var matchesAuthoredSuffix: Bool {
        guard !authored.isEmpty else { return true }
        guard let before = textDocumentProxy.documentContextBeforeInput, !before.isEmpty,
              (textDocumentProxy.selectedText ?? "").isEmpty else { return false }
        return before.hasSuffix(authored) || authored.hasSuffix(before)
    }

    func configureField() {
        // The keyboard window tracks the host's appearance, including a system-wide
        // appearance change while editing. A controller override freezes the old trait.
        observedKeyboardType = textDocumentProxy.keyboardType
        switch observedKeyboardType {
        case .numberPad, .decimalPad, .asciiCapableNumberPad: layout = .digits
        case .numbersAndPunctuation: layout = .numbers
        default: layout = .letters
        }
        updateCapitalization()
    }

    func clearContent() {
        stopRepeating()
        for view in content.arrangedSubviews { view.removeFromSuperview() }
        for view in toolbar.arrangedSubviews { view.removeFromSuperview() }
        letterKeys = []
        suggestionButtons = []
        shiftButton = nil
    }

    func button(_ title: String, symbol: String? = nil, special: Bool = false, action: (() -> Void)? = nil) -> KeyButton {
        let key = KeyButton(type: .custom)
        key.special = special
        key.setTitle(symbol == nil ? title : nil, for: .normal)
        if let symbol {
            key.setImage(UIImage(systemName: symbol), for: .normal)
            key.setPreferredSymbolConfiguration(.init(pointSize: 19, weight: .regular), forImageIn: .normal)
        }
        key.accessibilityLabel = title
        key.titleLabel?.font = .systemFont(ofSize: title.count == 1 ? 22 : 17, weight: title.count == 1 ? .medium : .regular, width: .standard)
        if title.count == 1 {
            key.titleLabel?.transform = CGAffineTransform(translationX: 0, y: -1.33).scaledBy(x: 0.94, y: 1)
        }
        key.titleLabel?.adjustsFontSizeToFitWidth = true
        key.tintColor = .label
        key.setTitleColor(.label, for: .normal)
        if let action { key.addAction(UIAction { _ in action() }, for: .touchUpInside) }
        return key
    }

    func showKeys() {
        clearContent()
        toolbar.axis = .horizontal
        toolbar.spacing = 0
        toolbar.distribution = .fill
        if !toolbar.constraints.contains(where: { $0.firstAttribute == .height }) {
            toolbar.heightAnchor.constraint(equalToConstant: 42).isActive = true
        }
        content.addArrangedSubview(toolbar)
        if instruction != nil {
            let finish = button("Done", special: true) { [weak self] in self?.showReview() }
            let label = UILabel()
            label.font = .preferredFont(forTextStyle: .footnote)
            label.text = instruction?.isEmpty == false ? instruction : "Type an instruction"
            label.textAlignment = .center
            label.accessibilityIdentifier = "rewriteInstruction"
            toolbar.addArrangedSubview(label)
            toolbar.addArrangedSubview(finish)
        } else {
            for index in 0..<3 {
                let key = button("")
                key.flat = true
                key.titleLabel?.font = .systemFont(ofSize: 17)
                key.setTitleColor(.label.withAlphaComponent(0.78), for: .normal)
                toolbar.addArrangedSubview(key)
                if let first = suggestionButtons.first { key.widthAnchor.constraint(equalTo: first.widthAnchor).isActive = true }
                suggestionButtons.append(key)
                if index < 2 {
                    let line = UIView()
                    line.backgroundColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.23, alpha: 1) : UIColor(red: 208/255, green: 210/255, blue: 215/255, alpha: 1) }
                    line.translatesAutoresizingMaskIntoConstraints = false
                    key.addSubview(line)
                    NSLayoutConstraint.activate([
                        line.trailingAnchor.constraint(equalTo: key.trailingAnchor),
                        line.centerYAnchor.constraint(equalTo: key.centerYAnchor),
                        line.widthAnchor.constraint(equalToConstant: 1),
                        line.heightAnchor.constraint(equalToConstant: 24)
                    ])
                }
                key.addAction(UIAction { [weak self, weak key] _ in
                    if let word = key?.currentTitle, !word.isEmpty { self?.acceptSuggestion(word) }
                }, for: .touchUpInside)
            }
            let rewrite = button("Rewrite", symbol: "wand.and.stars") { [weak self] in self?.beginRewrite() }
            rewrite.flat = true
            rewrite.tintColor = .secondaryLabel
            rewrite.setPreferredSymbolConfiguration(.init(pointSize: 13, weight: .medium), forImageIn: .normal)
            toolbar.addArrangedSubview(rewrite)
            rewrite.widthAnchor.constraint(equalToConstant: 49.5).isActive = true
        }
        let rows = UIStackView()
        keyRows = rows
        rows.axis = .vertical
        rows.spacing = 11
        rows.distribution = .fillEqually
        content.addArrangedSubview(rows)
        switch layout {
        case .letters:
            addRow(Array("qwertyuiop").map(String.init), to: rows)
            addRow(Array("asdfghjkl").map(String.init), to: rows, inset: true)
            addRow(["Shift"] + Array("zxcvbnm").map(String.init) + ["Delete"], to: rows)
        case .numbers:
            addRow(Array("1234567890").map(String.init), to: rows)
            addRow(["-", "/", ":", ";", "(", ")", Locale.current.currencySymbol ?? "$", "&", "@", "\""], to: rows)
            addRow(["#+=", ".", ",", "?", "!", "'", "Delete"], to: rows)
        case .symbols:
            addRow(Array("[]{}#%^*+=").map(String.init), to: rows)
            addRow(["_", "\\", "|", "~", "<", ">", Locale.current.currencySymbol == "$" ? "€" : "$", "£", Locale.current.currencySymbol == "$" ? "¥" : "€", "•"], to: rows)
            addRow(["123", ".", ",", "?", "!", "'", "Delete"], to: rows)
        case .emoji:
            addRow(Array("😀😃😄😁😅😂🤣🥲").map(String.init), to: rows)
            addRow(Array("😊😍😘😎🤔🫡🙌👏").map(String.init), to: rows)
            addRow(["👍","🙏","❤️","✨","🔥","🎉","💯","Delete"], to: rows)
        case .digits:
            for row in ["123", "456", "789"] { addRow(Array(row).map(String.init), to: rows) }
            addRow(["Globe", observedKeyboardType == .decimalPad ? "." : "ABC", "0", "Delete"], to: rows)
            refreshTyping()
            return
        }
        var bottom = [layout == .letters ? "123" : "ABC"]
        if layout != .emoji { bottom.append("Emoji") }
        if needsInputModeSwitchKey { bottom.append("Globe") }
        if observedKeyboardType == .emailAddress { bottom.append("@") }
        bottom.append("space")
        if observedKeyboardType == .URL || observedKeyboardType == .emailAddress { bottom.append(".") }
        bottom.append("return")
        addRow(bottom, to: rows, bottom: true)
        refreshTyping()
    }

    func addRow(_ names: [String], to stack: UIStackView, inset: Bool = false, bottom: Bool = false) {
        stack.addArrangedSubview(KeyRow(keys: names.map(makeKey), names: names, inset: inset, bottom: bottom))
    }

    func makeKey(_ name: String) -> UIButton {
        switch name {
        case "Shift":
            let key = button("Shift", symbol: "shift", special: true) { [weak self] in
                guard let self else { return }
                if Date().timeIntervalSince(lastShift) < 0.35 { shift = .locked }
                else { shift = shift == .off ? .once : .off }
                lastShift = Date()
                updateLetterKeys()
            }
            shiftButton = key
            return key
        case "Delete":
            let key = button("Delete", symbol: "delete.left", special: true)
            key.addAction(UIAction { [weak self] _ in self?.startDeleting() }, for: .touchDown)
            key.addAction(UIAction { [weak self] _ in self?.stopRepeating() }, for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
            key.accessibilityActivateHandler = { [weak self] in self?.erase(); return true }
            return key
        case "ABC", "123", "#+=", "Emoji":
            return button(name, symbol: name == "Emoji" ? "face.smiling" : nil, special: true) { [weak self] in
                self?.layout = name == "ABC" ? .letters : (name == "123" ? .numbers : (name == "#+=" ? .symbols : .emoji))
                self?.showKeys()
            }
        case "Globe":
            let key = button("Next keyboard", symbol: "globe", special: true)
            key.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
            return key
        case "space":
            let key = button("space") { [weak self] in self?.space() }
            key.setTitle(nil, for: .normal)
            let pan = UILongPressGestureRecognizer(target: self, action: #selector(moveCursor(_:)))
            pan.minimumPressDuration = 0.38
            pan.allowableMovement = 14
            key.addGestureRecognizer(pan)
            return key
        case "return":
            return button(returnLabel, symbol: returnLabel == "return" ? "return" : nil, special: true) { [weak self] in
                guard let self else { return }
                if instruction != nil { showReview() }
                else { commitComposition(); finishObservation(); type("\n") }
            }
        default:
            let key = button(name) { [weak self] in
                guard let self else { return }
                type(layout == .letters && shift != .off ? name.uppercased() : name)
            }
            if name.count == 1 {
                key.previewSurface = view
                if name.first?.isLetter == true && layout == .letters { letterKeys.append((name, key)) }
            }
            return key
        }
    }

    var returnLabel: String {
        switch textDocumentProxy.returnKeyType {
        case .send: return "send"
        case .go: return "go"
        case .search, .google, .yahoo: return "search"
        case .done: return "done"
        case .next: return "next"
        case .join: return "join"
        default: return "return"
        }
    }

    @objc func moveCursor(_ gesture: UILongPressGestureRecognizer) {
        guard instruction == nil else { return }
        if gesture.state == .began { panOrigin = gesture.location(in: view).x; panOffset = 0; authored = ""; commitComposition() }
        let location = Int((gesture.location(in: view).x - panOrigin) / 8)
        if gesture.state == .changed && location != panOffset {
            textDocumentProxy.adjustTextPosition(byCharacterOffset: location - panOffset)
            panOffset = location
        }
    }

    func startDeleting() {
        erase()
        stopRepeating()
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.42, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.09, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.erase() }
                }
            }
        }
    }

    func stopRepeating() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }
}

private final class KeyboardSurface: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}

final class KeyButton: UIButton {
    weak var previewSurface: UIView?
    private var preview: UILabel?

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard superview is KeyRow else { return super.point(inside: point, with: event) }
        return bounds.insetBy(dx: -7, dy: -5.5).contains(point)
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let began = super.beginTracking(touch, with: event)
        if began { UIDevice.current.playInputClick() }
        return began
    }

    private func updatePreview() {
        preview?.removeFromSuperview()
        preview = nil
        guard isHighlighted, let surface = previewSurface, let title = currentTitle,
              !UIAccessibility.isVoiceOverRunning else { return }
        let rect = convert(bounds, to: surface)
        let size = CGSize(width: max(42, rect.width + 10), height: 43)
        let x = min(max(2, rect.midX - size.width / 2), surface.bounds.width - size.width - 2)
        let label = UILabel(frame: CGRect(origin: CGPoint(x: x, y: max(0, rect.minY - size.height + 2)), size: size))
        label.text = title
        label.font = .systemFont(ofSize: 28)
        label.textAlignment = .center
        label.backgroundColor = .secondarySystemBackground
        label.layer.cornerRadius = 8
        label.layer.masksToBounds = true
        label.isUserInteractionEnabled = false
        label.isAccessibilityElement = false
        surface.addSubview(label)
        preview = label
    }

    var flat = false { didSet { configureColors() } }
    var special = false { didSet { configureColors() } }
    var accessibilityActivateHandler: (() -> Bool)?
    override func accessibilityActivate() -> Bool { accessibilityActivateHandler?() ?? super.accessibilityActivate() }
    override var isHighlighted: Bool { didSet { configureColors(); updatePreview() } }
    func configureColors() {
        layer.cornerRadius = 7.5
        layer.cornerCurve = .continuous
        let flat = flat
        let pressed = isHighlighted
        backgroundColor = UIColor { trait in
            if pressed { return .systemGray }
            if flat { return .clear }
            return trait.userInterfaceStyle == .dark ? UIColor(white: 61/255, alpha: 1) : .white
        }
    }
}
