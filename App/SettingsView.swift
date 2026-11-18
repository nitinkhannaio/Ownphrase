import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var notebook: Notebook
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var phase

    @State private var observesWriting = true
    @State private var key = ""
    @State private var message: String?
    @State private var confirmation: Confirmation?
    @State private var reminderEnabled = false
    @State private var reminderTime = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var reminderBusy = false
    @State private var notificationDenied = false
    @State private var notificationError: String?

    private enum Confirmation { case erase, removeKey }

    var body: some View {
        Form {
            Section("iPhone keyboard") {
                Text("In Settings, open General → Keyboard → Keyboards → Add New Keyboard and choose Ownphrase. Tap Ownphrase and turn on Allow Full Access for rewrites and your notebook.")
                Text("Touch and hold the globe in any text field to choose Ownphrase. To put it first in your keyboard list, use Edit on the Keyboards screen.")
                    .foregroundStyle(.secondary)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                NavigationLink("Try the keyboard") { PlaygroundView() }
            }
            Section {
                if notebook.hasKey {
                    Label("Key saved on this iPhone", systemImage: "key.fill")
                }
                SecureField(notebook.hasKey ? "Replacement OpenAI API key" : "OpenAI API key", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .privacySensitive()
                Button(notebook.hasKey ? "Replace key" : "Save key") { saveKey() }
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if notebook.hasKey {
                    Button("Remove key", role: .destructive) { confirmation = .removeKey }
                }
            } header: { Text("OpenAI") } footer: {
                Text("Rewrite sends the passage, your instruction, and learned writing preferences to OpenAI using your key. Your notebook is stored on this iPhone.")
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
                Button("Erase notebook and learned voice", role: .destructive) { confirmation = .erase }
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
        .onDisappear { key = "" }
        .confirmationDialog(confirmation == .erase ? "Erase your notebook?" : "Remove your OpenAI key?",
                            isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }),
                            titleVisibility: .visible, presenting: confirmation) { action in
            Button(action == .erase ? "Erase notebook" : "Remove key", role: .destructive) {
                do {
                    switch action {
                    case .erase: try OwnStore().erase()
                    case .removeKey: try APIKeyStore.remove()
                    }
                    key = ""
                    notebook.refresh()
                } catch {
                    message = error.localizedDescription
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { action in
            Text(action == .erase
                 ? "This permanently erases saved drafts, accepted rewrites, lessons, and learned preferences from this iPhone."
                 : "Rewrites will require a new key. Your notebook stays on this iPhone.")
        }
        .alert("Ownphrase", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private func saveKey() {
        do {
            let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return }
            try APIKeyStore.save(value)
            key = ""
            notebook.refresh()
            message = "Key saved."
        } catch {
            message = error.localizedDescription
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
