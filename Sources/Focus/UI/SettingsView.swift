import SwiftUI
import AppKit
import UniformTypeIdentifiers
import FocusCore

struct SettingsView: View {
    @EnvironmentObject var app: AppController
    @State private var rejected = false

    var body: some View {
        TabView {
            ModesTab(rejected: $rejected)
                .tabItem { Label("Modes", systemImage: "square.stack") }
            SchedulesTab(rejected: $rejected)
                .tabItem { Label("Schedules", systemImage: "calendar") }
            GeneralTab(rejected: $rejected)
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .alert("Change not saved", isPresented: $rejected) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(app.lastError ?? "This change isn't allowed during an active block.")
        }
    }
}

private struct ModesTab: View {
    @EnvironmentObject var app: AppController
    @Binding var rejected: Bool
    @State private var selection: UUID?

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                List(selection: $selection) {
                    ForEach(app.state.modes) { mode in
                        Label(mode.name, systemImage: mode.symbol).tag(mode.id)
                    }
                }
                .listStyle(.sidebar)
                Button("Add Mode", systemImage: "plus", action: addMode)
                    .buttonStyle(.glass)
            }
            .padding(12)
            .frame(width: 190)
            Divider()
            if let mode = app.state.modes.first(where: { $0.id == selection }) {
                ModeEditor(mode: mode, rejected: $rejected).id(mode.id)
            } else {
                ContentUnavailableView("Select a Mode", systemImage: "square.stack")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { if selection == nil { selection = app.state.modes.first?.id } }
    }

    private func addMode() {
        let mode = Mode(id: UUID(), name: "New Mode", symbol: "circle", domains: [], appBundleIDs: [])
        app.update { $0.modes.append(mode) }
        selection = mode.id
    }
}

private struct ModeEditor: View {
    @EnvironmentObject var app: AppController
    @Binding var rejected: Bool
    @State private var draft: Mode
    @State private var domainsText: String

    init(mode: Mode, rejected: Binding<Bool>) {
        _draft = State(initialValue: mode)
        _domainsText = State(initialValue: mode.domains.joined(separator: "\n"))
        _rejected = rejected
    }

    var body: some View {
        Form {
            Section("Mode") {
                LabeledContent("Name") {
                    TextField("", text: $draft.name)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("SF Symbol") {
                    HStack {
                        TextField("", text: $draft.symbol)
                            .multilineTextAlignment(.trailing)
                        Image(systemName: draft.symbol)
                            .frame(width: 24)
                    }
                }
            }
            Section {
                TextEditor(text: $domainsText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 120)
            } header: {
                Text("Domains")
            } footer: {
                Text("One per line.")
            }
            Section("Apps") {
                ForEach(draft.appBundleIDs, id: \.self) { bundleID in
                    LabeledContent {
                        Button(role: .destructive) {
                            draft.appBundleIDs.removeAll { $0 == bundleID }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    } label: {
                        Text(bundleID).lineLimit(1)
                    }
                }
                Button("Add App…", action: pickApp)
            }
            Section {
                HStack {
                    Spacer()
                    Button("Save", action: save)
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(filePath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        if !draft.appBundleIDs.contains(bundleID) { draft.appBundleIDs.append(bundleID) }
    }

    private func save() {
        var mode = draft
        mode.name = mode.name.trimmingCharacters(in: .whitespaces)
        mode.domains = normalizeDomains(domainsText)
        draft = mode
        domainsText = mode.domains.joined(separator: "\n")
        let saved = mode
        if !app.update({ state in
            if let i = state.modes.firstIndex(where: { $0.id == saved.id }) { state.modes[i] = saved }
        }) { rejected = true }
    }
}

private struct SchedulesTab: View {
    @EnvironmentObject var app: AppController
    @Binding var rejected: Bool
    @State private var selection: UUID?

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                List(selection: $selection) {
                    ForEach(app.state.schedules) { schedule in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(modeName(schedule.modeID))
                                .opacity(schedule.enabled ? 1 : 0.5)
                            Text("\(weekdayLetters(schedule.weekdays)) · \(Theme.clock(clockDate(schedule.startMinute)))–\(Theme.clock(clockDate(schedule.endMinute)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(schedule.id)
                    }
                }
                .listStyle(.sidebar)
                Button("Add Schedule", systemImage: "plus", action: addSchedule)
                    .buttonStyle(.glass)
                    .disabled(app.state.modes.isEmpty)
            }
            .padding(12)
            .frame(width: 210)
            Divider()
            if let schedule = app.state.schedules.first(where: { $0.id == selection }) {
                ScheduleEditor(schedule: schedule, rejected: $rejected).id(schedule.id)
            } else {
                ContentUnavailableView("Select a Schedule", systemImage: "calendar")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func modeName(_ id: UUID) -> String {
        app.state.modes.first { $0.id == id }?.name ?? "Missing Mode"
    }

    private func addSchedule() {
        guard let modeID = app.state.modes.first?.id else { return }
        let schedule = Schedule(id: UUID(), modeID: modeID, weekdays: [2, 3, 4, 5, 6],
                                startMinute: 540, endMinute: 1020, enabled: true)
        app.update { $0.schedules.append(schedule) }
        selection = schedule.id
    }
}

private struct ScheduleEditor: View {
    @EnvironmentObject var app: AppController
    @Binding var rejected: Bool
    @State private var draft: Schedule
    @State private var start: Date
    @State private var end: Date

    init(schedule: Schedule, rejected: Binding<Bool>) {
        _draft = State(initialValue: schedule)
        _start = State(initialValue: clockDate(schedule.startMinute))
        _end = State(initialValue: clockDate(schedule.endMinute))
        _rejected = rejected
    }

    var body: some View {
        Form {
            Section("Mode") {
                Picker("Mode", selection: $draft.modeID) {
                    ForEach(app.state.modes) { Text($0.name).tag($0.id) }
                }
                Toggle("Enabled", isOn: $draft.enabled)
            }
            Section("Days") {
                HStack(spacing: 6) {
                    ForEach(1...7, id: \.self) { day in
                        let on = draft.weekdays.contains(day)
                        Button(Calendar.current.veryShortWeekdaySymbols[day - 1]) {
                            if on { draft.weekdays.remove(day) } else { draft.weekdays.insert(day) }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(on ? Color.accentColor : Color.secondary.opacity(0.15)))
                        .foregroundStyle(on ? Color.white : Color.primary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            Section("Hours") {
                DatePicker("From", selection: $start, displayedComponents: .hourAndMinute)
                DatePicker("Until", selection: $end, displayedComponents: .hourAndMinute)
            }
            Section {
                HStack {
                    Spacer()
                    Button("Save", action: save)
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(draft.weekdays.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func save() {
        var schedule = draft
        schedule.startMinute = minuteOfDay(start)
        schedule.endMinute = minuteOfDay(end)
        draft = schedule
        let saved = schedule
        if !app.update({ state in
            if let i = state.schedules.firstIndex(where: { $0.id == saved.id }) { state.schedules[i] = saved }
        }) { rejected = true }
    }
}

private struct GeneralTab: View {
    @EnvironmentObject var app: AppController
    @Binding var rejected: Bool
    @State private var draft = FocusCore.Settings()

    var body: some View {
        Form {
            Section("Emergency Exit") {
                Toggle("Enabled", isOn: $draft.emergencyEnabled)
                Stepper("Wait: \(draft.emergencyWaitMinutes) min", value: $draft.emergencyWaitMinutes, in: 1...240)
                Stepper("Phrase length: \(draft.emergencyPhraseLength)", value: $draft.emergencyPhraseLength, in: 20...400, step: 20)
            }
            Section {
                HStack {
                    Spacer()
                    Button("Save", action: save)
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { draft = app.state.settings }
    }

    private func save() {
        let d = draft
        if !app.update({ state in
            state.settings.emergencyEnabled = d.emergencyEnabled
            state.settings.emergencyWaitMinutes = d.emergencyWaitMinutes
            state.settings.emergencyPhraseLength = d.emergencyPhraseLength
        }) { rejected = true }
    }
}

private func clockDate(_ minute: Int) -> Date {
    Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
}

private func minuteOfDay(_ date: Date) -> Int {
    let c = Calendar.current.dateComponents([.hour, .minute], from: date)
    return (c.hour ?? 0) * 60 + (c.minute ?? 0)
}

private func weekdayLetters(_ days: Set<Int>) -> String {
    let symbols = Calendar.current.veryShortWeekdaySymbols
    return days.sorted().map { symbols[$0 - 1] }.joined()
}

private func normalizeDomains(_ text: String) -> [String] {
    text.split(whereSeparator: \.isNewline)
        .map { line -> String in
            var d = line.trimmingCharacters(in: .whitespaces).lowercased()
            for prefix in ["https://", "http://", "www."] where d.hasPrefix(prefix) {
                d.removeFirst(prefix.count)
            }
            return d
        }
        .filter { !$0.isEmpty }
}
