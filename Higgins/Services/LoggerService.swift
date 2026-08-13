import Foundation
import Observation

func log(
    _ message: String,
    type: LoggerService.LogType = .info,
    file: String = #fileID,
    line: Int = #line
) {
    Task { @MainActor in
        LoggerService.shared.record(message, type: type, file: file, line: line)
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
    }

    enum LogType: String, CaseIterable, Equatable, Identifiable {
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"

        var id: Self { self }
    }

    static let shared = LoggerService()

    private(set) var logs: [LogEntry] = []

    private init() {}

    func record(_ message: String, type: LogType = .info, file: String, line: Int) {
        let entry = LogEntry(id: UUID(), timestamp: Date(), message: message, type: type)
        logs.append(entry)
        print("[\(entry.timestamp.formatted(.iso8601))] [\(type.rawValue)] [\(file):\(line)] \(message)")
    }

    func clear() {
        logs.removeAll()
    }

    func export() -> String {
        logs.map { entry in
            "[\(entry.timestamp.formatted(.iso8601))] [\(entry.type.rawValue)] \(entry.message)"
        }
        .joined(separator: "\n")
    }
}
