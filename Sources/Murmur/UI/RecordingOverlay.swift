import AppKit
import SwiftUI

/// The floating readout that appears while dictating, and the only place the
/// app tells the user anything in the moment.
///
/// It lives in a non-activating panel: the app being dictated into must keep
/// keyboard focus, otherwise the ⌘V we synthesise afterwards lands in the
/// wrong place.
@MainActor
final class RecordingOverlay {
    private var panel: NSPanel?
    private let model = OverlayModel()
    /// Tracked so the panel is only ordered front on the transition into
    /// visibility; the level feeds in 30 times a second and re-fronting the
    /// window at that rate makes it flicker.
    private var isVisible = false

    private static let size = CGSize(width: 300, height: 60)
    /// Distance from the bottom of the active screen's visible frame.
    private static let bottomInset: CGFloat = 96

    func update(state: DictationState, level: Float) {
        model.level = level

        switch state {
        case .recording:
            model.kind = .listening
            model.caption = "Listening"
            show()
        case .transcribing:
            model.kind = .working
            model.caption = "Transcribing"
            show()
        case .notice(let message):
            model.kind = .message(isProblem: false)
            model.caption = message
            show()
        case .failure(let message):
            model.kind = .message(isProblem: true)
            model.caption = message
            show()
        case .idle:
            hide()
        }
    }

    private func show() {
        guard !isVisible else { return }
        if panel == nil { panel = makePanel() }
        guard let panel else { return }
        reposition(panel)
        // orderFrontRegardless, never makeKeyAndOrderFront: showing this must
        // not change which app is frontmost.
        panel.orderFrontRegardless()
        isVisible = true
    }

    private func hide() {
        guard isVisible else { return }
        panel?.orderOut(nil)
        isVisible = false
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.nonactivatingPanel, .borderless, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: OverlayView(model: model))
        return panel
    }

    private func reposition(_ panel: NSPanel) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        let origin = CGPoint(
            x: frame.midX - Self.size.width / 2,
            y: frame.minY + Self.bottomInset
        )
        panel.setFrame(NSRect(origin: origin, size: Self.size), display: false)
    }
}

enum OverlayKind: Equatable {
    case listening
    case working
    case message(isProblem: Bool)
}

@MainActor
private final class OverlayModel: ObservableObject {
    @Published var level: Float = 0
    @Published var caption: String = "Listening"
    @Published var kind: OverlayKind = .listening
}

private struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    private static let barCount = 14

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(symbolColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 5) {
                Text(model.caption)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isMessage ? .primary : .secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !isMessage {
                    meter
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }

    private var isMessage: Bool {
        if case .message = model.kind { return true }
        return false
    }

    private var symbolName: String {
        switch model.kind {
        case .listening: return "mic.fill"
        case .working: return "ellipsis"
        case .message(let isProblem): return isProblem ? "exclamationmark.triangle.fill" : "info.circle.fill"
        }
    }

    private var symbolColor: Color {
        switch model.kind {
        case .listening: return .red
        case .working: return .secondary
        case .message(let isProblem): return isProblem ? .orange : .secondary
        }
    }

    private var meter: some View {
        HStack(spacing: 3) {
            ForEach(0..<Self.barCount, id: \.self) { index in
                Capsule()
                    .fill(isLit(index) ? Color.red.opacity(0.85) : Color.secondary.opacity(0.22))
                    .frame(width: 4, height: height(for: index))
            }
        }
        .animation(.easeOut(duration: 0.08), value: model.level)
    }

    /// Amplitude is compressed with a square root so quiet speech still moves
    /// the meter; raw linear peak barely registers at conversational volume.
    private var normalized: Double {
        min(1, sqrt(Double(model.level)) * 1.6)
    }

    private func isLit(_ index: Int) -> Bool {
        guard case .listening = model.kind else { return false }
        return Double(index) / Double(Self.barCount) < normalized
    }

    private func height(for index: Int) -> CGFloat {
        // A gentle arch so the meter reads as a waveform rather than a bar chart.
        let centred = abs(Double(index) - Double(Self.barCount - 1) / 2)
        let falloff = 1 - (centred / Double(Self.barCount)) * 0.9
        let base = 5.0
        let span = 13.0 * falloff
        return CGFloat(base + span * (isLit(index) ? max(0.35, normalized) : 0.12))
    }
}
