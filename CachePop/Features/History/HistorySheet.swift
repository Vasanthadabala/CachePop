import SwiftUI

/// Every clean so far, newest first, with the lifetime total.
struct HistorySheet: View {
    let history: CleanHistory
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.m) {
                IconTile(symbolName: "clock.arrow.circlepath", size: 32, tone: .accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("History")
                        .font(AppTheme.Typography.title)
                    Text(history.records.isEmpty
                         ? "Cleans you run appear here."
                         : "\(ByteSize.string(history.lifetimeFreedBytes)) freed in \(history.records.count) \(history.records.count == 1 ? "clean" : "cleans"), measured from your disk.")
                        .font(AppTheme.Typography.callout)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }
            .padding(AppTheme.Spacing.l)

            RowDivider(leadingInset: 0)

            ScrollView {
                // Lazy: the history is never trimmed, so it can hold years of cleans.
                LazyVStack(spacing: 0) {
                    ForEach(Array(history.records.enumerated()), id: \.element.id) { index, record in
                        if index > 0 { RowDivider(leadingInset: AppTheme.Spacing.m) }
                        HistoryRow(record: record)
                    }
                }
                .card()
                .padding(AppTheme.Spacing.l)
            }
            .frame(minHeight: 160, maxHeight: 380)
            .background(AppTheme.Colors.canvas)

            RowDivider(leadingInset: 0)

            HStack {
                Button("Clear History…") { isConfirmingClear = true }
                    .disabled(history.records.isEmpty)
                Spacer()
                Button("Done") { dismiss() }
                    .primaryAction()
                    .keyboardShortcut(.defaultAction)
            }
            .padding(AppTheme.Spacing.l)
        }
        .frame(width: 480)
        .background(AppTheme.Colors.raised)
        .confirmationDialog("Clear the history?", isPresented: $isConfirmingClear) {
            Button("Clear History", role: .destructive) { history.clear() }
        } message: {
            Text("Only the list of past cleans is removed. Nothing on disk changes.")
        }
    }
}

private struct HistoryRow: View {
    let record: CleanRecord

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.date.formatted(date: .abbreviated, time: .shortened))
                    .font(AppTheme.Typography.headline)
                Text(summary)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: AppTheme.Spacing.s)
            VStack(alignment: .trailing, spacing: 2) {
                SizeText(bytes: record.freedBytes, emphasized: true)
                Text(record.wasMeasured ? "freed" : "estimated")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textTertiary)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.m)
        .padding(.vertical, 8)
    }

    private var summary: String {
        let listed = record.titles.prefix(3).joined(separator: ", ")
        let more = record.titles.count > 3 ? " and \(record.titles.count - 3) more" : ""
        var text = "\(record.itemCount) \(record.itemCount == 1 ? "item" : "items"): \(listed)\(more)"
        if record.trashBytes > 0 { text += " · \(ByteSize.string(record.trashBytes)) to the Trash" }
        return text
    }
}
