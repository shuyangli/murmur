import Foundation
import OSLog

enum Log {
    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let asr = Logger(subsystem: subsystem, category: "asr")
    static let output = Logger(subsystem: subsystem, category: "output")
    static let app = Logger(subsystem: subsystem, category: "app")

    private static let subsystem = "com.shuyangli.murmur"
}
