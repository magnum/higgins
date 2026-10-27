import Foundation
import Observation

func log(
    _ message: String,
    type: LoggerService.LogType = .info,
    detail: String? = nil,
    file: String = #fileID,
    line: Int = #line
) {
    Task { @MainActor in
        LoggerService.shared.record(message, type: type, detail: detail, file: file, line: line)
    }
}

@MainActor
@Observable
final class LoggerService {
    struct LogEntry: Equatable, Identifiable {
        let id: UUID
        let timestamp: Date
        let message: String
        let type: LogType
        /// Optional long-form content, such as a request or response body.
        let detail: String?
        let file: String
        let line: Int
    }

    enum LogType: String, CaseIterable, Equatable, Identifiable {
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"

        var id: Self { self }
    }

    static let shared = LoggerService()

    /// Oldest entries are dropped beyond this, so request/response bodies don't grow memory unbounded.
    private static let maxEntries = 5000

    private(set) var logs: [LogEntry] = []

    private init() {}

    func record(_ message: String, type: LogType = .info, detail: String? = nil, file: String, line: Int) {
        let entry = LogEntry(
            id: UUID(),
            timestamp: Date(),
            message: message,
            type: type,
            detail: detail,
            file: file,
            line: line
        )
        logs.append(entry)
        if logs.count > Self.maxEntries {
            logs.removeFirst(logs.count - Self.maxEntries)
        }
        print("[\(entry.timestamp.formatted(.iso8601))] [\(type.rawValue)] [\(file):\(line)] \(message)")
    }

    func clear() {
        logs.removeAll()
    }

    func export(_ entries: [LogEntry]? = nil) -> String {
        (entries ?? logs).map(Self.format).joined(separator: "\n")
    }

    static func format(_ entry: LogEntry) -> String {
        let header = "[\(entry.timestamp.formatted(.iso8601))] [\(entry.type.rawValue)] \(entry.message)"
        guard let detail = entry.detail else { return header }
        return "\(header)\n\(detail)"
    }
}
