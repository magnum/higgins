import AppKit
import SwiftUI

struct LogView: View {
    private let logger = LoggerService.shared

    @State private var searchText = ""
    @State private var selectedType: LoggerService.LogType?
    @State private var lineLimit = 100
    @State private var selectedEntry: LoggerService.LogEntry?

    var body: some View {
        Group {
            if let selectedEntry {
                LogEntryDetail(entry: selectedEntry) {
                    self.selectedEntry = nil
                }
            } else {
                VStack(spacing: 0) {
                    LogToolbar(
                        searchText: $searchText,
                        selectedType: $selectedType,
                        lineLimit: $lineLimit,
                        onClear: logger.clear,
                        onCopy: copyLogs
                    )

                    Divider()

                    List(visibleLogs) { entry in
                        Button {
                            selectedEntry = entry
                        } label: {
                            LogEntryRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    /// The last `lineLimit` matching entries, newest first.
    private var visibleLogs: [LoggerService.LogEntry] {
        let matching = logger.logs.filter { entry in
            let matchesSearch = searchText.isEmpty
                || entry.message.localizedCaseInsensitiveContains(searchText)
                || entry.detail?.localizedCaseInsensitiveContains(searchText) == true
            let matchesType = selectedType == nil || entry.type == selectedType
            return matchesSearch && matchesType
        }
        return Array(matching.suffix(max(lineLimit, 1)).reversed())
    }

    private func copyLogs() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logger.export(visibleLogs), forType: .string)
    }
}

private struct LogToolbar: View {
    @Binding var searchText: String
    @Binding var selectedType: LoggerService.LogType?
    @Binding var lineLimit: Int

    let onClear: () -> Void
    let onCopy: () -> Void

    var body: some View {
        HStack {
            TextField("Search logs…", text: $searchText)
                .textFieldStyle(.roundedBorder)

            Picker("Level", selection: $selectedType) {
                Text("All").tag(nil as LoggerService.LogType?)
                ForEach(LoggerService.LogType.allCases) { type in
                    Text(type.label).tag(type as LoggerService.LogType?)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 250)

            Text("Last")
                .foregroundStyle(.secondary)
            TextField("Lines", value: $lineLimit, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
                .help("Number of most recent log lines to show")

            Button("Clear Logs", systemImage: "trash", action: onClear)
                .labelStyle(.iconOnly)
                .help("Clear logs")

            Button("Copy Logs", systemImage: "doc.on.doc", action: onCopy)
                .labelStyle(.iconOnly)
                .help("Copy the visible logs")
        }
        .padding()
    }
}

private struct LogEntryRow: View {
    let entry: LoggerService.LogEntry
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(entry.timestamp, format: .dateTime.hour().minute().second())
                    .foregroundStyle(.secondary)

                LogTypeBadge(type: entry.type)

                if entry.detail != nil {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.secondary)
                        .help("Has details")
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .font(.caption)

            Text(entry.message)
                .font(.system(.body, design: .monospaced))
                .lineLimit(2)
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        .listRowInsets(.init(top: 2, leading: 8, bottom: 2, trailing: 8))
        .background(isHovered ? Color.secondary.opacity(0.1) : .clear)
        .onHover { isHovered = $0 }
    }
}

/// Full content of a single log entry, with a way back to the list.
private struct LogEntryDetail: View {
    let entry: LoggerService.LogEntry
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Back to Logs", systemImage: "chevron.left", action: onBack)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Copy", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(LoggerService.format(entry), forType: .string)
                }
                .help("Copy this log entry")
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(entry.timestamp, format: .dateTime.year().month().day().hour().minute().second())
                            .foregroundStyle(.secondary)
                        LogTypeBadge(type: entry.type)
                        Spacer()
                        Text(verbatim: "\(entry.file):\(entry.line)")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)

                    Text(entry.message)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)

                    if let detail = entry.detail {
                        Text(detail)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 6))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
        }
    }
}

private struct LogTypeBadge: View {
    let type: LoggerService.LogType

    var body: some View {
        Text(type.rawValue)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .foregroundStyle(type.color)
            .background(type.color.opacity(0.1), in: .rect(cornerRadius: 4))
    }
}

private extension LoggerService.LogType {
    var label: LocalizedStringResource {
        switch self {
        case .info:
            "Info"
        case .warning:
            "Warning"
        case .error:
            "Error"
        }
    }

    var color: Color {
        switch self {
        case .info:
            .primary
        case .warning:
            .orange
        case .error:
            .red
        }
    }
}

#Preview {
    LogView()
}
