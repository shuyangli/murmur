import AppKit
import MurmurCore

/// Sizes for the subtitle readout, and the wrapping that has to agree with them.
///
/// The line breaks are chosen here rather than left to SwiftUI because the
/// readout only stays steady if the breaks are known in advance: lines already
/// on screen must not move when new words arrive. Measuring against the same
/// font the view draws with is what keeps our breaks and the rendered text in
/// agreement — a character count cannot, since it would be wrong for Latin and
/// CJK text by different amounts.
@MainActor
enum OverlayMetrics {
    static let lineCount = SubtitleText.defaultLineCount
    static let lineSpacing: CGFloat = 2

    static let subtitleWidth: CGFloat = 460
    private static let horizontalPadding: CGFloat = 14
    private static let verticalPadding: CGFloat = 11
    /// Height of the icon-and-meter row above the text.
    private static let headerHeight: CGFloat = 18
    /// Gap between the header and the first line of text.
    private static let headerGap: CGFloat = 8

    /// Matches `.font(.callout)` on the `Text` views that draw the lines.
    private static let font = NSFont.preferredFont(forTextStyle: .callout)

    private static var lineHeight: CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }

    /// Space the text block always occupies, full or not, so that filling from
    /// one line to three never resizes the panel.
    static var subtitleBlockHeight: CGFloat {
        lineHeight * CGFloat(lineCount) + lineSpacing * CGFloat(lineCount - 1)
    }

    static var subtitleHeight: CGFloat {
        verticalPadding * 2 + headerHeight + headerGap + subtitleBlockHeight
    }

    private static var availableTextWidth: CGFloat {
        subtitleWidth - horizontalPadding * 2
    }

    static func layOutSubtitle(_ text: String) -> [String] {
        SubtitleText.visibleLines(of: text, maxLines: lineCount) { candidate in
            width(of: candidate) <= availableTextWidth
        }
    }

    private static func width(of text: String) -> CGFloat {
        NSAttributedString(string: text, attributes: [.font: font]).size().width
    }
}
