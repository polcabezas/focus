import SwiftUI
import FocusCore

struct EmergencyView: View {
    @EnvironmentObject var app: AppController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onClose: () -> Void
    @State private var step = Step.explain
    @State private var typed = ""
    @State private var reason = ""
    @State private var rejectedReason = false

    private enum Step { case explain, phrase, reason }

    private var phrase: String { app.state.emergency?.phrase ?? "" }

    private var unlockAt: Date {
        (app.state.emergency?.requestedAt ?? app.now)
            .addingTimeInterval(Double(app.state.settings.emergencyWaitMinutes) * 60)
    }

    private var stepTransition: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity)
    }

    var body: some View {
        Group {
            switch step {
            case .explain: explain.transition(stepTransition)
            case .phrase: phraseStep.transition(stepTransition)
            case .reason: reasonStep.transition(stepTransition)
            }
        }
        .overlayPanel()
        .animation(reduceMotion ? nil : .snappy, value: step)
    }

    private var explain: some View {
        VStack(spacing: 24) {
            OverlayHeader(symbol: "exclamationmark.triangle.fill", tint: .red, title: "Emergency exit",
                          message: "Every active block stops right now.")
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, text in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 16, alignment: .leading)
                        Text(text)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            OverlayActions {
                Button("Cancel", action: cancel)
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
            } trailing: {
                Button("Start") {
                    if app.state.emergency == nil { app.requestEmergency() }
                    step = .phrase
                }
                .buttonStyle(.glassProminent)
                .tint(.red)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var steps: [String] {
        [
            "This ends the current block.",
            "Type the text below exactly.",
            "Wait \(app.state.settings.emergencyWaitMinutes) minutes",
            "Why are you leaving?",
        ]
    }

    private var phraseStep: some View {
        VStack(spacing: 24) {
            OverlayHeader(symbol: "keyboard", tint: .red, title: "Type the phrase",
                          message: "Type the text below exactly. Pasting isn't allowed.")
            VStack(alignment: .leading, spacing: 6) {
                Text(phrase)
                    .font(.body.monospaced())
                    .textSelection(.disabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                TextField("Type the phrase", text: $typed)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .autocorrectionDisabled()
                    .onChange(of: typed) { old, new in
                        // Pasting is not allowed: any large jump in length clears the field.
                        if new.count - old.count > 2 { typed = "" }
                    }
            }
            OverlayActions {
                Button("Cancel", action: cancel)
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
            } trailing: {
                Button("Continue") { step = .reason }
                    .buttonStyle(.glassProminent)
                    .tint(.red)
                    .keyboardShortcut(.defaultAction)
                    .disabled(phrase.isEmpty || typed != phrase)
            }
        }
    }

    private var reasonStep: some View {
        VStack(spacing: 24) {
            if app.now < unlockAt {
                OverlayHeader(symbol: "hourglass", tint: .red, title: "Wait",
                              message: "You can explain yourself when the timer ends.")
                OverlayTimer(seconds: unlockAt.timeIntervalSince(app.now))
            } else {
                let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                OverlayHeader(symbol: "exclamationmark.triangle.fill", tint: .red, title: "Why are you leaving?",
                              message: "At least 20 characters.")
                VStack(alignment: .leading, spacing: 6) {
                    Text("Reason")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    OverlayTextEditor(text: $reason, minHeight: 120)
                    Text("\(trimmed.count) of 20 characters minimum")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    if rejectedReason {
                        Text("The wait isn't over yet.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                OverlayActions {
                    Button("Cancel", action: cancel)
                        .buttonStyle(.glass)
                        .keyboardShortcut(.cancelAction)
                } trailing: {
                    Button("Exit Block") {
                        if app.confirmEmergency(reason: trimmed) {
                            onClose()
                        } else {
                            rejectedReason = true
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.red)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.count < 20)
                }
            }
        }
    }

    private func cancel() {
        app.cancelEmergency()
        onClose()
    }
}
