import AppKit
import MurmurCore
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
    private var currentLayout: OverlayLayout?

    /// Distance from the bottom of the active screen's visible frame.
    private static let bottomInset: CGFloat = 96

    func update(state: DictationState, level: Float, partial: String) {
        model.level = level
        model.subtitle = SubtitleText.tail(of: partial)

        switch state {
        case .recording:
            model.kind = .listening
            model.caption = "Listening"
            show(layout: model.subtitle.isEmpty ? .compact : .subtitle)
        case .transcribing:
            model.kind = .working
            model.caption = "Transcribing"
            show(layout: model.subtitle.isEmpty ? .compact : .subtitle)
        case .notice(let message):
            model.kind = .message(isProblem: false)
            model.caption = message
            model.subtitle = ""
            show(layout: .message)
        case .failure(let message):
            model.kind = .message(isProblem: true)
            model.caption = message
            model.subtitle = ""
            show(layout: .message)
        case .idle:
            hide()
        }
    }

    private func show(layout: OverlayLayout) {
        if panel == nil { panel = makePanel() }
        guard let panel else { return }

        // Resize whenever the layout changes, including mid-utterance as the
        // first words arrive and the readout grows into a subtitle.
        if layout != currentLayout {
            currentLayout = layout
            reposition(panel, for: layout)
        }

        guard !isVisible else { return }
        // orderFrontRegardless, never makeKeyAndOrderFront: showing this must
        // not change which app is frontmost.
        panel.orderFrontRegardless()
        isVisible = true
    }

    private func hide() {
        guard isVisible else { return }
        panel?.orderOut(nil)
        isVisible = false
        currentLayout = nil
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: OverlayLayout.compact.size),
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

    private func reposition(_ panel: NSPanel, for layout: OverlayLayout) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        let size = layout.size
        // Pinned by its top edge, so growing into subtitle mode extends the
        // panel downward and the mic and meter stay exactly where the eye
        // already found them. Anchoring the bottom instead would shove the
        // whole header upward the moment the first words arrived.
        let anchorTop = frame.minY + Self.bottomInset + OverlayLayout.compact.size.height
        let origin = CGPoint(
            x: frame.midX - size.width / 2,
            y: anchorTop - size.height
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

/// The readout has a small number of fixed shapes rather than sizing itself to
/// its content: an explicit `setFrame` is predictable, where relying on SwiftUI
/// intrinsic sizing to drive a borderless panel is not.
enum OverlayLayout: Equatable {
    case compact
    case subtitle
    case message

    var size: CGSize {
        switch self {
        case .compact: return CGSize(width: 300, height: 60)
        case .subtitle: return CGSize(width: 460, height: 124)
        case .message: return CGSize(width: 360, height: 68)
        }
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
    @Published var subtitle: String = ""
    @Published var kind: OverlayKind = .listening
}

private struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    private static let barCount = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if !model.subtitle.isEmpty {
                Text(model.subtitle)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Words arrive a chunk at a time, so ease them in rather
                    // than having the block snap to a new size.
                    .animation(.easeOut(duration: 0.15), value: model.subtitle)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(symbolColor)
                .frame(width: 18)

            if isMessage {
                Text(model.caption)
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(model.caption)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                meter
            }
        }
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
