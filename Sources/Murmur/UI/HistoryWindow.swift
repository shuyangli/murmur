import SwiftUI

/// The full dictation log: searchable, copyable, and disposable.
struct HistoryWindow: View {
    @EnvironmentObject private var controller: DictationController
    @EnvironmentObject private var preferences: Preferences

    @State private var query = ""
    @State private var selection: HistoryEntry.ID?
    @State private var confirmingClearAll = false

    var body: some View {
        VStack(spacing: 0) {
            if filtered.isEmpty {
                emptyState
            } else {
                list
            }
            Divider()
            toolbar
        }
        .frame(minWidth: 480, minHeight: 380)
        .searchable(text: $query, placement: .toolbar, prompt: "Search dictations")
        .navigationTitle("Dictation History")
    }

    private var filtered: [HistoryEntry] {
        let entries = controller.history.entries
        guard !query.isEmpty else { return entries }
        return entries.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    private var list: some View {
        List(filtered, selection: $selection) { entry in
            HistoryRow(entry: entry)
                .contextMenu {
                    Button("Copy") { TextInjector.copy(entry.text) }
                    Button("Delete", role: .destructive) { controller.history.delete(entry) }
                }
                .tag(entry.id)
        }
        .listStyle(.inset)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text(query.isEmpty ? "No dictations yet" : "No matches")
                .font(.title3)
            Text(query.isEmpty
                 ? "Hold \(preferences.triggerKey.label) anywhere to dictate."
                 : "Try a different search.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var toolbar: some View {
        HStack {
            Text("\(controller.history.entries.count) of \(preferences.historyLimit) kept")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Copy") {
                guard let entry = filtered.first(where: { $0.id == selection }) else { return }
                TextInjector.copy(entry.text)
            }
            .disabled(selection == nil)

            Button("Delete") {
                guard let entry = filtered.first(where: { $0.id == selection }) else { return }
                controller.history.delete(entry)
                selection = nil
            }
            .disabled(selection == nil)

            Button("Clear All…") { confirmingClearAll = true }
                .disabled(controller.history.entries.isEmpty)
        }
        .padding(10)
        .confirmationDialog(
            "Delete every saved dictation?",
            isPresented: $confirmingClearAll,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                controller.history.deleteAll()
                selection = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. Transcripts already pasted are unaffected.")
        }
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.text)
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Text(entry.createdAt, format: .dateTime.month().day().hour().minute())
                Text("·")
                Text("\(entry.audioDuration, format: .number.precision(.fractionLength(1)))s spoken")
                Text("·")
                Text("\(entry.transcriptionDuration, format: .number.precision(.fractionLength(2)))s to transcribe")
                if let target = entry.targetApplication {
                    Text("·")
                    Text(applicationName(for: target))
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    /// Turns a bundle identifier into something a person recognises.
    private func applicationName(for bundleID: String) -> String {
        bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    }
}
