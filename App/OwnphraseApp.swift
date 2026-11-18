import SwiftUI

@main
struct OwnphraseApp: App {
    @Environment(\.scenePhase) private var phase
    @StateObject private var notebook = Notebook()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(notebook)
                .onChange(of: phase) { _, newValue in
                    if newValue == .active { notebook.refresh() }
                }
                .task { notebook.refresh() }
        }
    }
}

@MainActor
final class Notebook: ObservableObject {
    @Published private(set) var entries: [OwnEntry] = []
    @Published private(set) var lessons: [DailyLesson] = []
    @Published private(set) var profile = ""
    @Published private(set) var readError: String?
    @Published private(set) var hasKey = false

    func refresh() {
        do {
            let store = OwnStore()
            entries = try store.history()
            lessons = try store.daily(on: Date())
            profile = try store.profile()
            hasKey = try APIKeyStore.load() != nil
            readError = nil
        } catch {
            readError = error.localizedDescription
        }
    }
}

enum SectionTab { case today, notebook, settings }

struct HomeView: View {
    @EnvironmentObject private var notebook: Notebook
    @State private var tab = SectionTab.today

    var body: some View {
        TabView(selection: $tab) {
            Tab("Today", systemImage: "sun.max", value: .today) {
                NavigationStack {
                    TodayView(openSettings: { tab = .settings })
                }
            }
            Tab("Notebook", systemImage: "book.pages", value: .notebook) {
                NavigationStack { NotebookView() }
            }
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                NavigationStack { SettingsView() }
            }
        }
        .tint(.accentColor)
        .onChange(of: tab) { notebook.refresh() }
    }
}

struct TodayView: View {
    @EnvironmentObject private var notebook: Notebook
    let openSettings: () -> Void

    var body: some View {
        List {
            if let message = notebook.readError {
                Section { Label(message, systemImage: "exclamationmark.triangle") }
            }
            if !notebook.hasKey {
                Section {
                    Button(action: openSettings) {
                        Label("Set up your keyboard", systemImage: "keyboard")
                    }
                }
            }
            Section {
                if notebook.lessons.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "text.book.closed")
                            .font(.title).foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        Text("No lessons yet today").font(.title3.weight(.semibold))
                        Text("As you write, look here for recurring word choices and English lessons from rewrites you accept.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                } else {
                    ForEach(notebook.lessons, id: \.id) { lesson in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(lesson.lesson).font(.headline)
                            if lesson.count > 1 && !lesson.original.isEmpty {
                                Text("Seen in \(lesson.count) rewrites")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if !lesson.original.isEmpty { Passage(label: "Original", text: lesson.original) }
                            if !lesson.corrected.isEmpty { Passage(label: "Accepted", text: lesson.corrected) }
                        }
                        .padding(.vertical, 6)
                    }
                }
            } header: {
                Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
            }
            Section {
                NavigationLink {
                    PlaygroundView()
                } label: {
                    Label("Try the keyboard", systemImage: "square.and.pencil")
                }
            }
        }
        .navigationTitle("Today")
        .refreshable { notebook.refresh() }
    }
}

struct NotebookView: View {
    @EnvironmentObject private var notebook: Notebook

    var body: some View {
        List {
            if let message = notebook.readError {
                Section { Label(message, systemImage: "exclamationmark.triangle") }
            }
            Section("My voice") {
                if notebook.profile.isEmpty {
                    Text("As you type and choose rewrites, your writing patterns and preferences will appear here.")
                        .foregroundStyle(.secondary)
                } else {
                    Text(notebook.profile).textSelection(.enabled)
                }
            }
            Section("Accepted rewrites") {
                if notebook.entries.isEmpty {
                    Text("Your original drafts and the rewrites you choose will appear here.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(notebook.entries, id: \.id) { entry in
                        NavigationLink {
                            EntryView(entry: entry)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entry.text).lineLimit(2)
                                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
            }
        }
        .navigationTitle("Notebook")
        .refreshable { notebook.refresh() }
    }
}

private struct EntryView: View {
    let entry: OwnEntry

    var body: some View {
        List {
            Section(entry.date.formatted(date: .long, time: .shortened)) {
                Passage(label: "Original draft", text: entry.original)
                Passage(label: "Accepted rewrite", text: entry.text)
            }
            if !entry.context.isEmpty {
                Section("Writing context") { Text(entry.context) }
            }
            if !entry.preference.isEmpty {
                Section("Voice observation") { Text(entry.preference) }
            }
            if !entry.lesson.isEmpty {
                Section("English lesson") { Text(entry.lesson) }
            }
        }
        .navigationTitle("Rewrite")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct Passage: View {
    let label: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(text).textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }
}

struct PlaygroundView: View {
    @EnvironmentObject private var notebook: Notebook
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Type a message, then use Rewrite on the Ownphrase keyboard. To choose the keyboard, touch and hold the globe.")
                .font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $draft)
                .focused($focused)
                .accessibilityLabel("Practice draft")
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
            if !draft.isEmpty {
                Button("Clear practice draft") { draft = "" }
            }
        }
        .padding()
        .navigationTitle("Try the keyboard")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { notebook.refresh() }
    }
}
