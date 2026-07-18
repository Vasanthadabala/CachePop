import SwiftUI

struct FileInfoGrid: View {
    let item: CareScanDetailItem

    private var rows: [(String, String)] {
        [
            ("Modified:", item.modifiedText),
            ("Location:", item.subtitle),
            ("Size:", item.formattedSize),
            ("File type:", fileType)
        ]
    }

    private var fileType: String {
        let ext = URL(fileURLWithPath: item.path).pathExtension
        if ext.isEmpty {
            return item.kind
        }
        return ext.uppercased()
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 26, verticalSpacing: 14) {
            ForEach(rows, id: \.0) { row in
                GridRow {
                    Text(row.0)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.44))
                    Text(row.1)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.86))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
            }
        }
    }
}
