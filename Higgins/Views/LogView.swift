import AppKit
import SwiftUI

struct LogView: View {
    private let logger = LoggerService.shared

    @State private var searchText = ""
    @State private var selectedType: LoggerService.LogType?
    @State private var autoScroll = true

    var body: some View {
        VStack(spacing: 0) {
            LogToolbar(
                searchText: $searchText,
                selectedType: $selectedType,
                autoScroll: $autoScroll,
                onClear: logger.clear,
                onCopy: copyLogs
            )

            Divider()

            ScrollViewReader { proxy in
                List(filteredLogs) { entry in
                    LogEntryRow(entry: entry)
                }
                .onChange(of: logger.logs.last?.id) {
                    guard autoScroll, let lastID = filteredLogs.last?.id else { return }
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    private var filteredLogs: [LoggerService.LogEntry] {
        logger.logs.filter { entry in
            let matchesSearch = searchText.isEmpty
                || entry.message.localizedCaseInsensitiveContains(searchText)
            let matchesType = selectedType == nil || entry.type == selectedType
            return matchesSearch && matchesType
        }
    }

    private func copyLogs() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logger.export(), forType: .string)
    }
}

private struct LogToolbar: View {
    @Binding var searchText: String
    @Binding var selectedType: LoggerService.LogType?
    @Binding var autoScroll: Bool

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
            .frame(width: 250)

            Spacer()

            Toggle("Auto-scroll", systemImage: "arrow.down.to.line", isOn: $autoScroll)
                .toggleStyle(.button)
                .labelStyle(.iconOnly)
                .help("Auto-scroll to latest log")

            Button("Clear Logs", systemImage: "trash", action: onClear)
                .labelStyle(.iconOnly)
                .help("Clear logs")

            Button("Copy Logs", systemImage: "doc.on.doc", action: onCopy)
                .labelStyle(.iconOnly)
                .help("Copy logs")
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

                Text(entry.type.rawValue)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .foregroundStyle(entry.type.color)
                    .background(entry.type.color.opacity(0.1), in: .rect(cornerRadius: 4))
            }
            .font(.caption)

            Text(entry.message)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
        .listRowInsets(.init(top: 2, leading: 8, bottom: 2, trailing: 8))
        .background(isHovered ? Color.secondary.opacity(0.1) : .clear)
        .onHover { isHovered = $0 }
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
