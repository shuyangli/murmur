import AppKit
import SwiftUI

/// A small floating readout that appears while dictating.
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

    private static let size = CGSize(width: 188, height: 56)
    /// Distance from the bottom of the active screen's visible frame.
    private static let bottomInset: CGFloat = 96

    func update(state: DictationState, level: Float) {
        model.level = level

        switch state {
        case .recording:
            model.caption = "Listening"
            model.isBusy = false
            show()
        case .transcribing:
            model.caption = "Transcribing"
            model.isBusy = true
            show()
        case .idle, .notice, .failure:
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

@MainActor
private final class OverlayModel: ObservableObject {
    @Published var level: Float = 0
    @Published var caption: String = "Listening"
    @Published var isBusy: Bool = false
}

private struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    private static let barCount = 14

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: model.isBusy ? "ellipsis" : "mic.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(model.isBusy ? Color.secondary : Color.red)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 5) {
                Text(model.caption)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                meter
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
        model.isBusy ? false : Double(index) / Double(Self.barCount) < normalized
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
