import OSLog

/// Central log policy. Categories are deliberately finite so release logging
/// cannot grow ad-hoc channels that expose tokens, payloads, device contents,
/// or raw audio. Call sites log lifecycle/outcome facts only.
enum AppLog {
    static let subsystem = "com.ryujou.Maurya"
    static let categoryNames: Set<String> = [
        "lifecycle", "bluetooth", "effects", "sharing", "ota", "persistence",
    ]

    static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    static let bluetooth = Logger(subsystem: subsystem, category: "bluetooth")
    static let effects = Logger(subsystem: subsystem, category: "effects")
    static let sharing = Logger(subsystem: subsystem, category: "sharing")
    static let ota = Logger(subsystem: subsystem, category: "ota")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
}
