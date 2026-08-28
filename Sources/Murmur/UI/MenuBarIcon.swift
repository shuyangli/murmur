import SwiftUI

/// The status item glyph. It doubles as the recording indicator, so a glance
/// at the menu bar always says whether Murmur is listening.
struct MenuBarIcon: View {
    let state: DictationState

    var body: some View {
        Image(systemName: symbolName)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
    }

    private var symbolName: String {
        switch state {
        case .recording: return "waveform.circle.fill"
        case .transcribing: return "ellipsis.circle"
        case .failure: return "exclamationmark.circle"
        case .notice: return "info.circle"
        case .idle: return "waveform"
        }
    }

    private var tint: Color {
        switch state {
        case .recording: return .red
        case .failure: return .orange
        default: return .primary
        }
    }
}
