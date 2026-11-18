import SwiftUI

enum RewriteTone: String, CaseIterable, Identifiable {
    case myVoice = "My voice", friendly = "Friendly", professional = "Professional", casual = "Casual"
    case fix = "Fix grammar", shorter = "Shorter"
    var id: Self { self }
    var prompt: String {
        switch self {
        case .myVoice: "Polish this passage in my own voice."
        case .friendly: "Use a warm, friendly tone without adding familiarity or facts."
        case .professional: "Use a clear professional tone. Keep my voice and avoid corporate jargon."
        case .casual: "Use relaxed, conversational English in my voice."
        case .fix: "Correct only grammar, spelling and punctuation. Keep my words and register."
        case .shorter: "Make this more concise while preserving meaning, tone and every fact."
        }
    }
}

enum PanelPage {
    case tones(String, Bool, String?)
    case working(RewriteTone)
    case result(String, Int, Int, Bool, String?)
    case notice(String, String)
    case setup(String)
}

struct RewritePanel: View {
    let page: PanelPage
    let close: () -> Void
    let choose: (RewriteTone) -> Void
    let change: () -> Void
    let move: (Int) -> Void
    let use: () -> Void
    let copy: () -> Void
    let openSetup: () -> Void
    @State private var expanded = false
    @ScaledMetric(relativeTo: .body) private var previewHeight = 44
    @Environment(\.dynamicTypeSize) private var size

    private var title: String {
        switch page {
        case .tones: "Rewrite"
        case .working(let tone): tone.rawValue
        case .result: "Choose a rewrite"
        case .notice(let title, _): title
        case .setup: "Connect OpenAI"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.headline).accessibilityAddTraits(.isHeader)
                    if !size.isAccessibilitySize, case .tones(_, let selected, _) = page {
                        Text(selected ? "Selected text" : "Text before cursor").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark").font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel("Back to typing")
            }
            .padding(.leading, 16).padding(.trailing, 4)
            Divider()
            switch page {
            case let .tones(text, selected, error):
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if let error {
                            Label(error, systemImage: "exclamationmark.circle").font(.subheadline)
                                .accessibilityAddTraits(.isHeader)
                        }
                        if !size.isAccessibilitySize || error == nil {
                            if size.isAccessibilitySize || expanded {
                                previewButton(text, selected: selected)
                            } else {
                                ViewThatFits(in: .vertical) {
                                    Text(text).font(.body).fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    previewButton(text, selected: selected)
                                }.frame(height: previewHeight).foregroundStyle(.secondary)
                            }
                        }
                        if !selected && text.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 {
                            Text("Select the passage in your message to rewrite it.").font(.subheadline)
                        } else {
                            if !size.isAccessibilitySize {
                                Text("Choose a tone to rewrite with OpenAI.").font(.footnote).foregroundStyle(.secondary)
                            }

                            LazyVGrid(columns: size.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 102), spacing: 8)], spacing: 8) {
                                ForEach(RewriteTone.allCases) { tone in
                                    Button { choose(tone) } label: {
                                        Text(tone.rawValue).font(.subheadline.weight(.semibold))
                                            .multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 44)
                                            .padding(.horizontal, 2)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(tone == .myVoice ? Color.white : Color.primary)
                                    .background(tone == .myVoice ? Color(uiColor: .systemIndigo) : Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 61/255, alpha: 1) : .white }), in: RoundedRectangle(cornerRadius: 10))
                                    .accessibilityHint("Rewrite this passage with OpenAI")
                                }
                            }
                        }
                    }.padding(.horizontal, 16).padding(.vertical, 8)
                }
            case .working:
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Rewriting…").font(.subheadline).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityElement(children: .combine)
            case let .notice(_, message):
                ScrollView { Text(message).frame(maxWidth: .infinity, alignment: .leading).padding(16) }
            case let .setup(message):
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(message).font(.subheadline)
                        SetupLink(action: { openSetup(); return .systemAction }) {
                            Label("Open Ownphrase", systemImage: "arrow.up.forward.app").frame(minHeight: 44)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 8)
                }
            case let .result(text, index, count, canReplace, status):
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if let status { Text(status).font(.subheadline).foregroundStyle(.secondary) }
                        Text(text).font(.body)
                        if !canReplace {
                            Text("Select the original to replace it, or copy this rewrite.").font(.footnote).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 8)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { resultActions(index, count, canReplace) }
                    ScrollView(.horizontal) { HStack(spacing: 8) { resultActions(index, count, canReplace) } }
                }.padding(.horizontal, 12).padding(.bottom, 4)
            }
        }.foregroundStyle(.primary)
    }

    private func previewButton(_ text: String, selected: Bool) -> some View {
        Button { expanded.toggle() } label: {
            HStack(spacing: 8) {
                Text(text).multilineTextAlignment(.leading).lineLimit(expanded ? nil : (size.isAccessibilitySize ? 1 : 2))
                Spacer(minLength: 0)
                Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption)
            }.frame(minHeight: 44)
        }.buttonStyle(.plain).foregroundStyle(.secondary)
        .accessibilityLabel((selected ? "Selected text. " : "Text before cursor. ") + text)
        .accessibilityHint("Expand or collapse the preview")
    }

    @ViewBuilder private func resultActions(_ index: Int, _ count: Int, _ canReplace: Bool) -> some View {
        Button(action: change) { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }
            .accessibilityLabel("Change tone")
        if count > 1 {
            Button { move((index + 1) % count) } label: {
                HStack { Text("\(index + 1) of \(count)").monospacedDigit(); Image(systemName: "chevron.right") }
                    .frame(minHeight: 44)
            }.accessibilityLabel("Option \(index + 1) of \(count). Next option")
        }
        Spacer(minLength: 4)
        Button(action: canReplace ? use : copy) {
            Text(canReplace ? "Replace" : "Copy rewrite").fontWeight(.semibold)
                .fixedSize(horizontal: true, vertical: false).padding(.horizontal, 14).frame(minHeight: 44)
                .foregroundStyle(.white).background(Color(uiColor: .systemIndigo), in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
    }
}

/// Link offers a user-initiated URL handoff. The persistent setup route also works
/// when an iOS version or host declines a keyboard's request to foreground its app.
struct SetupLink<Content: View>: View {
    let action: () -> OpenURLAction.Result
    @ViewBuilder let label: () -> Content
    var body: some View {
        Link(destination: URL(string: "ownphrase://setup/openai")!, label: label)
            .environment(\.openURL, OpenURLAction { _ in
                action()
            })
    }
}
