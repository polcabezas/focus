import SwiftUI
import AppKit

/// Centered alert-style header: hierarchical SF Symbol, title, optional supporting message.
struct OverlayHeader: View {
    let symbol: String
    var tint: Color = .accentColor
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 56))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Large rounded countdown, like the Clock app. Colour via `.foregroundStyle` on the caller.
struct OverlayTimer: View {
    let seconds: TimeInterval

    var body: some View {
        Text(Theme.timeLeft(seconds))
            .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
            .contentTransition(.numericText())
            .frame(maxWidth: .infinity)
    }
}

/// Multi-line input with the rounded-border look of a system text field.
struct OverlayTextEditor: View {
    @Binding var text: String
    var placeholder: String?
    var minHeight: CGFloat = 90

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .font(.body)
            if text.isEmpty, let placeholder {
                Text(placeholder)
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .allowsHitTesting(false)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color(nsColor: .separatorColor)))
    }
}

/// Bottom action row: secondary on the left, primary on the right, in one glass container.
struct OverlayActions<Leading: View, Trailing: View>: View {
    let leading: Leading
    let trailing: Trailing

    init(@ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                leading
                Spacer(minLength: 0)
                trailing
            }
        }
        .controlSize(.large)
    }
}

extension View {
    /// The overlay surface: Liquid Glass, 440pt wide, 24pt padding, radius 26. Follows the system appearance.
    func overlayPanel() -> some View {
        self
            .padding(24)
            .frame(width: 440)
            .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }
}
