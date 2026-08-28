import Foundation

/// A downloaded model described the way a person would recognise it.
public struct ModelDescription: Equatable, Sendable {
    /// The engine the files belong to.
    public let engineName: String
    /// Which build of that engine, when there is more than one.
    public let variant: String?

    public init(engineName: String, variant: String? = nil) {
        self.engineName = engineName
        self.variant = variant
    }
}

/// Turns the cache directory names the model host uses into readable labels.
///
/// The on-disk layout is not ours — it comes from FluidAudio — so this maps
/// what it happens to write (`nemotron-multilingual/latin/2240ms`) onto the
/// same words the settings UI uses elsewhere, and degrades to a tidied
/// directory name for anything it does not recognise.
public enum ModelNaming {

    public static func describe(pathComponents: [String]) -> ModelDescription {
        guard let root = pathComponents.first else {
            return ModelDescription(engineName: "Unknown model")
        }

        switch root {
        case "nemotron-multilingual":
            return ModelDescription(
                engineName: "Nemotron 3.5 ASR",
                variant: nemotronVariant(Array(pathComponents.dropFirst()))
            )
        case let name where name.hasPrefix("parakeet"):
            return ModelDescription(engineName: "Parakeet TDT v3")
        default:
            return ModelDescription(engineName: prettified(root))
        }
    }

    private static func nemotronVariant(_ components: [String]) -> String? {
        var parts: [String] = []
        if let vocabulary = components.first {
            parts.append(vocabularyLabel(vocabulary))
        }
        if components.count > 1, let chunk = chunkLabel(components[1]) {
            parts.append(chunk)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The host ships a vocabulary-pruned build for Latin-script languages and
    /// a full-vocabulary one for everything else.
    private static func vocabularyLabel(_ directory: String) -> String {
        switch directory {
        case "latin": return "Western European languages"
        case "multilingual": return "All languages"
        default: return prettified(directory)
        }
    }

    /// Directory names are like "2240ms"; the readout updates once per chunk,
    /// so this is the number the settings UI shows too.
    private static func chunkLabel(_ directory: String) -> String? {
        guard directory.hasSuffix("ms"), let value = Int(directory.dropLast(2)) else { return nil }
        let seconds = Double(value) / 1000
        return String(format: "%.1f s chunks", seconds)
    }

    private static func prettified(_ name: String) -> String {
        name.replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
    }
}
