import SwiftUI
import FocusCore

extension InstalledBrowser {
    /// "Arc" rather than "Arc.app".
    var displayName: String {
        name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}

/// The "Start Session" module shown while nothing is blocking: mode tiles, For/Until duration, summary, Start, warnings.
struct SessionStarter: View {
    @EnvironmentObject var app: AppController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var modeID: UUID?
    @State private var kind = Kind.forDuration
    @State private var forMinutes = 60
    @State private var untilTime = Durations.roundedUp(Date().addingTimeInterval(3600), toMinutes: 5)
    @State private var isEditingMinutes = false
    @State private var draft = ""
    @State private var shake: CGFloat = 0
    @FocusState private var fieldFocused: Bool

    private static let presets = [15, 30, 60, 120, 240]

    private enum Kind: Hashable {
        case forDuration, until
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            modeTiles
            durationSection
            startButton
            ForEach(unconnectedBrowsers) { browser in
                warning(for: browser)
            }
        }
        .menuModule()
        .onAppear { if modeID == nil { modeID = app.state.modes.first?.id } }
    }

    // MARK: Mode

    @ViewBuilder
    private var modeTiles: some View {
        let scrolls = app.state.modes.count > 3
        let tiles = HStack(spacing: 6) {
            ForEach(app.state.modes) { mode in
                ModeTile(mode: mode, isSelected: mode.id == modeID, width: scrolls ? 72 : nil) {
                    select(mode.id)
                }
            }
        }
        if scrolls {
            ScrollView(.horizontal, showsIndicators: false) { tiles }
        } else {
            tiles
        }
    }

    private func select(_ id: UUID) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) {
            modeID = id
        }
    }

    // MARK: Duration

    private var duration: Int {
        switch kind {
        case .forDuration: forMinutes
        case .until: Durations.minutesUntil(clockTime: untilTime, now: app.now)
        }
    }

    private var durationSection: some View {
        VStack(spacing: 12) {
            Picker("Duration", selection: $kind) {
                Text("For").tag(Kind.forDuration)
                Text("Until").tag(Kind.until)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch kind {
            case .forDuration: forControls
            case .until: untilControls
            }

            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
    }

    private var summary: String {
        switch kind {
        case .forDuration:
            "Ends at \(Theme.clock(app.now.addingTimeInterval(TimeInterval(duration * 60))))"
        case .until:
            "\(Durations.format(duration)) from now"
        }
    }

    private var forControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                stepButton(up: false)
                readout
                stepButton(up: true)
            }
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(Self.presets, id: \.self) { preset in
                        presetChip(preset)
                    }
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.upArrow) {
            stepMinutes(up: true)
            return .handled
        }
        .onKeyPress(.downArrow) {
            stepMinutes(up: false)
            return .handled
        }
    }

    private var readoutFont: Font {
        .system(size: 40, weight: .semibold, design: .rounded).monospacedDigit()
    }

    /// Click to type a duration. Shows the value; becomes a text field while editing.
    @ViewBuilder
    private var readout: some View {
        if isEditingMinutes {
            TextField("Duration", text: $draft)
                .labelsHidden()
                .textFieldStyle(.plain)
                .font(readoutFont)
                .multilineTextAlignment(.center)
                .focused($fieldFocused)
                .onSubmit(commitDraft)
                .onExitCommand { isEditingMinutes = false }
                .modifier(Shake(progress: shake))
                .frame(maxWidth: .infinity)
                .onAppear { fieldFocused = true }
        } else {
            Button {
                draft = Durations.format(forMinutes)
                isEditingMinutes = true
            } label: {
                Text(Durations.format(forMinutes))
                    .font(readoutFont)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .animation(reduceMotion ? nil : .snappy, value: forMinutes)
            .accessibilityLabel("Duration, \(Durations.format(forMinutes))")
            .accessibilityHint("Type a duration")
        }
    }

    private func commitDraft() {
        if let parsed = Durations.parse(draft) {
            forMinutes = parsed
            isEditingMinutes = false
        } else {
            draft = Durations.format(forMinutes)
            withAnimation(reduceMotion ? nil : .linear(duration: 0.35)) { shake += 2 }
        }
    }

    private func stepButton(up: Bool) -> some View {
        Button {
            stepMinutes(up: up)
        } label: {
            Image(systemName: up ? "plus" : "minus")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .disabled(Durations.stepped(forMinutes, up: up) == forMinutes)
        .accessibilityLabel(up ? "Longer" : "Shorter")
    }

    private func stepMinutes(up: Bool) {
        forMinutes = Durations.stepped(forMinutes, up: up)
    }

    @ViewBuilder
    private func presetChip(_ preset: Int) -> some View {
        let title = Self.presetLabel(preset)
        let selected = kind == .forDuration && forMinutes == preset
        Group {
            if selected {
                Button(title) { forMinutes = preset }.buttonStyle(.glassProminent)
            } else {
                Button(title) { forMinutes = preset }.buttonStyle(.glass)
            }
        }
        .controlSize(.small)
        .frame(maxWidth: .infinity)
    }

    private var untilControls: some View {
        DatePicker("Until", selection: $untilTime, displayedComponents: .hourAndMinute)
            .datePickerStyle(.field)
            .labelsHidden()
            .font(.system(size: 28, weight: .semibold, design: .rounded))
            .frame(maxWidth: .infinity)
    }

    private static func presetLabel(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h"
    }

    // MARK: Start

    private var startButton: some View {
        Button {
            if let modeID {
                app.startSession(modeID: modeID, minutes: duration)
            }
        } label: {
            Text(startTitle)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
        .frame(maxWidth: .infinity)
        // While the readout is being typed into, Return commits the text instead of starting.
        .disabled(modeID == nil || duration < 1 || isEditingMinutes)
    }

    private var startTitle: String {
        let name = app.state.modes.first { $0.id == modeID }?.name ?? "Session"
        return "Start \(name) · \(Durations.format(duration))"
    }

    // MARK: Warnings

    private var unconnectedBrowsers: [InstalledBrowser] {
        app.installedBrowsers.filter { app.browserSeen[$0.bundleID] == nil }
    }

    private func warning(for browser: InstalledBrowser) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("\(browser.displayName) hasn't connected yet. It will be closed during the session.")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One mode as a tile: a 34pt circle with the mode's symbol, and its name below.
private struct ModeTile: View {
    let mode: Mode
    let isSelected: Bool
    var width: CGFloat?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .frame(width: 34, height: 34)
                    .background {
                        if isSelected {
                            Circle().fill(Color.accentColor)
                        } else {
                            Circle().fill(.fill.tertiary)
                        }
                    }
                Text(mode.name)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .lineLimit(1)
            }
            .frame(width: width)
            .frame(maxWidth: width == nil ? CGFloat.infinity : nil)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mode, \(mode.name)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A short horizontal wobble for an invalid entry.
private struct Shake: GeometryEffect {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 6 * sin(progress * 2 * .pi), y: 0))
    }
}
