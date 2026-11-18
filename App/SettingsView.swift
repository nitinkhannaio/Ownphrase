import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var notebook: Notebook
    @EnvironmentObject private var setup: KeyboardSetup
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var phase

    @State private var observesWriting = true
    @State private var message: String?
    @State private var confirmErase = false
    @State private var reminderEnabled = false
    @State private var reminderTime = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var reminderBusy = false
    @State private var notificationDenied = false
    @State private var notificationError: String?


    var body: some View {
        Form {
            Section("Keyboard") {
                Button("Keyboard setup and OpenAI key") { setup.route = .general }
                NavigationLink("Try the keyboard") { PlaygroundView() }
            }
            Section {
                Toggle("Daily lesson reminder", isOn: Binding(
                    get: { reminderEnabled },
                    set: { enabled in Task { await setReminder(enabled) } }
                ))
                .disabled(reminderBusy)
                if reminderEnabled {
                    DatePicker("Remind me at", selection: $reminderTime, displayedComponents: .hourAndMinute)
                    Button("Save reminder time") { Task { await setReminder(true) } }
                        .disabled(reminderBusy)
                }
                if notificationDenied {
                    Text("Notifications are turned off for Ownphrase in iPhone Settings.")
                        .foregroundStyle(.secondary)
                    Button("Open notification settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                }
                if let notificationError { Text(notificationError).foregroundStyle(.secondary) }
            } header: { Text("Lessons") } footer: {
                Text("A local notification reminds you to review a lesson when there is a writing pattern or correction to review.")
            }
            Section {
                Toggle("Learn from everyday typing", isOn: Binding(
                    get: { observesWriting },
                    set: { enabled in
                        do {
                            try OwnStore().setObservationEnabled(enabled)
                            observesWriting = enabled
                        } catch {
                            message = error.localizedDescription
                        }
                    }
                ))
            } header: { Text("My voice") } footer: {
                Text("Keep counts of writing patterns on this iPhone. Full draft text is saved only for rewrites you accept.")
            }
            Section("Local data") {
                Button("Erase notebook and learned voice", role: .destructive) { confirmErase = true }
            }
        }
        .navigationTitle("Settings")
        .task {
            do { observesWriting = try OwnStore().observationEnabled() }
            catch { message = error.localizedDescription }
            await loadReminder()
        }
        .onChange(of: phase) { _, newValue in
            if newValue == .active { Task { await loadReminder() } }
        }
        .confirmationDialog("Erase your notebook?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Erase notebook", role: .destructive) {
                do {
                    try OwnStore().erase()
                    notebook.refresh()
                } catch {
                    message = error.localizedDescription
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently erases saved drafts, accepted rewrites, lessons, and learned preferences from this iPhone.")
        }
        .alert("Ownphrase", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private func loadReminder() async {
        do {
            let saved = try DailyReminders.settings()
            reminderEnabled = saved != nil
            if let saved {
                reminderTime = Calendar.current.date(bySettingHour: saved.hour, minute: saved.minute, second: 0, of: Date()) ?? reminderTime
            }
            notificationDenied = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
        } catch {
            notificationError = error.localizedDescription
        }
    }

    private func setReminder(_ enabled: Bool) async {
        guard !reminderBusy else { return }
        reminderBusy = true
        defer { reminderBusy = false }
        do {
            if enabled {
                let time = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
                try await DailyReminders.enable(hour: time.hour ?? 20, minute: time.minute ?? 0)
            } else {
                try DailyReminders.disable()
            }
            notificationError = nil
        } catch {
            notificationError = error.localizedDescription
        }
        await loadReminder()
    }
}

struct KeyboardSetupSheet: View {
    let route: KeyboardSetup.Route
    @EnvironmentObject private var setup: KeyboardSetup
    @EnvironmentObject private var notebook: Notebook
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var phase
    @State private var key = ""
    @State private var feedback: String?
    @State private var failure: String?
    @State private var confirmRemove = false
    @FocusState private var enteringKey: Bool

    var body: some View {
        NavigationStack {
            Form {
                if route == .keyboardAccess || (route == .general && !setup.hasUsedFullAccess) {
                    Section("Enable the keyboard") { activationSteps }
                }
                Section {
                    SecureField(notebook.hasKey ? "Replacement OpenAI API key" : "OpenAI API key", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .privacySensitive()
                        .focused($enteringKey)
                        .submitLabel(.done)
                        .onSubmit { if !key.isEmpty { saveKey() } }
                    Button(notebook.hasKey ? "Replace key" : "Save key") { saveKey() }
                        .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let feedback {
                        Label(feedback, systemImage: "checkmark.circle.fill").foregroundStyle(.tint)
                    } else if notebook.hasKey {
                        Label("A key is saved on this iPhone.", systemImage: "key")
                            .foregroundStyle(.secondary)
                    }
                    if notebook.hasKey {
                        Button("Remove key", role: .destructive) { confirmRemove = true }
                    }
                    Link("Create or manage an OpenAI key", destination: URL(string: "https://platform.openai.com/api-keys")!)
                    if let failure { Text(failure).foregroundStyle(.red) }
                } footer: {
                    Text("Ownphrase stores your key in this iPhone’s Keychain and uses it to send your passage, chosen tone, and voice preferences to OpenAI.")
                }
                if route == .openAI || (route == .general && setup.hasUsedFullAccess) {
                    Section {
                        DisclosureGroup("Keyboard setup") {
                            if setup.hasUsedFullAccess {
                                Label("Keyboard used with Full Access", systemImage: "checkmark.circle")
                                    .foregroundStyle(.secondary)
                            }
                            activationSteps
                        }
                    }
                }
            }
            .navigationTitle(route == .openAI ? "Connect OpenAI" : "Keyboard setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onAppear {
            do { try notebook.refreshKeyStatus() }
            catch { failure = error.localizedDescription }
        }
        .onChange(of: phase) { _, next in
            if next == .background { key = "" }
        }
        .onDisappear { key = "" }
        .confirmationDialog("Remove your OpenAI key?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove key", role: .destructive) { removeKey() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Rewrites will need a new key. Your notebook stays on this iPhone.") }
    }

    @ViewBuilder private var activationSteps: some View {
        Text("In iPhone Settings, open General → Keyboard → Keyboards → Add New Keyboard. Choose Ownphrase, then turn on Allow Full Access.")
        Text("Full Access lets Ownphrase use your OpenAI key for rewrites and save lessons in your local notebook.")
            .foregroundStyle(.secondary)
        Text("Hold the globe in a text field to choose Ownphrase. Use Edit in the Keyboards list to put it first.")
        Button("Open Ownphrase settings") {
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        }
    }

    private func saveKey() {
        do {
            try APIKeyStore.save(key)
            key = ""
            enteringKey = false
            try notebook.refreshKeyStatus()
            failure = nil
            feedback = "Key saved. Return to your draft to rewrite."
        } catch {
            failure = error.localizedDescription
        }
    }

    private func removeKey() {
        do {
            try APIKeyStore.remove()
            key = ""
            try notebook.refreshKeyStatus()
            failure = nil
            feedback = "Key removed."
        } catch {
            failure = error.localizedDescription
        }
    }
}
