//
//  MyClutterView.swift
//  CachePop
//
//  Created by Vasanth on 14/05/26.
//

import SwiftUI

struct MyClutterView: View {
    var onBack: () -> Void = {}

    var body: some View {
        MyClutterManager(onBack: onBack)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.top, 10)
            .padding(.trailing, 10)
            .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MyClutterManager: View {
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            MyClutterToolbar(onBack: onBack)

            HStack(spacing: 0) {
                MyClutterCategories()
                    .frame(width: 252)

                Divider()

                DuplicateFilesPane()
                    .frame(width: 284)

                Divider()

                DuplicatePreviewPane()
            }

            MyClutterBottomBar()
        }
        .background(Color(hex: 0xFBFBFD))
    }
}

private struct MyClutterToolbar: View {
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color(hex: 0x6F7DFF))

                    Text("Back")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Text("My Clutter Manager")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.black.opacity(0.92))

            Spacer()

            HStack(spacing: 28) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(hex: 0x6F7DFF))

                HStack(spacing: 6) {
                    Text("Sort by:")
                        .foregroundStyle(.black.opacity(0.92))

                    Text("Size")
                        .foregroundStyle(Color(hex: 0x6F7DFF))

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: 0x6F7DFF))
                }
                .font(.system(size: 16, weight: .bold, design: .rounded))
            }
        }
        .frame(height: 64)
        .padding(.horizontal, 28)
        .background(Color.white)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.black.opacity(0.06))
                .frame(height: 1)
        }
    }
}

private struct MyClutterCategories: View {
    private let categories = ["Large & Old Files", "Duplicates", "Similar Images", "Downloads"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(categories, id: \.self) { category in
                Text(category)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(category == "Duplicates" ? .black : .black.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 15)
                    .frame(height: 44)
                    .background {
                        if category == "Duplicates" {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(hex: 0xEAEFFF).opacity(0.72))
                        }
                    }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 42)
        .background(Color(hex: 0xFCFCFD))
    }
}

private struct DuplicateFilesPane: View {
    private let files = DuplicateFile.samples

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Duplicates")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
                .padding(.bottom, 12)

            Text("Identical copies of files that may be stored in different locations of your Mac. They may be wasting a significant amount of space.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.black.opacity(0.55))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 22)

            HStack(spacing: 6) {
                Text("Show:")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)

                Text("All Files")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0x6F7DFF))

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(hex: 0x6F7DFF))
            }
            .padding(.bottom, 30)

            VStack(spacing: 10) {
                ForEach(files) { file in
                    DuplicateFileRow(file: file)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .overlay(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(.black.opacity(0.08))
                .frame(width: 6)
                .padding(.vertical, 16)
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(.white)
                        .frame(width: 4, height: 168)
                        .padding(.top, 15)
                }
        }
    }
}

private struct DuplicateFileRow: View {
    let file: DuplicateFile

    var body: some View {
        HStack(spacing: 14) {
            ThumbnailView(kind: file.thumbnail)
                .frame(width: 42, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(file.name)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.92))
                    .lineLimit(1)

                Text(file.size)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.48))
            }

            Spacer()

            HStack(spacing: 0) {
                Text("\(file.selected)")
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Color(hex: 0x6F7DFF))

                Text("\(file.total)")
                    .foregroundStyle(.black.opacity(0.52))
                    .frame(width: 22, height: 22)
                    .background(Color(hex: 0xECEAF2))
            }
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .padding(.horizontal, 14)
        .frame(height: 62)
        .background {
            if file.isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0xDCE3FF), Color(hex: 0xE8ECFF)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
        }
    }
}

private struct DuplicatePreviewPane: View {
    private let thumbs = Array(repeating: ThumbnailKind.oasis, count: 8)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("Select:")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)

                Text("Smartly")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0x6F7DFF))

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(hex: 0x6F7DFF))
            }
            .padding(.top, 42)
            .padding(.bottom, 30)

            HStack(alignment: .top, spacing: 22) {
                VStack(spacing: 10) {
                    ForEach(thumbs.indices, id: \.self) { index in
                        SelectableThumbnail(isActive: index == 0, isChecked: index != 1)
                            .frame(width: 56, height: 48)
                    }
                }

                VStack(alignment: .leading, spacing: 24) {
                    OasisPreview()
                        .frame(maxWidth: .infinity)
                        .frame(height: 252)
                        .clipped()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("oasis_1 copy.png")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.black.opacity(0.92))

                        HStack(spacing: 7) {
                            Text("Macintosh HD")
                            Text("›")
                            Text("Users")
                            Text("›")
                            Text("MainUser")
                            Text("›")
                            Text("MyPhotos")
                            Image(systemName: "magnifyingglass.circle.fill")
                        }
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.black.opacity(0.35))

                        FileInfoGrid()
                    }
                    .padding(.leading, 2)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 24)
    }
}

private struct SelectableThumbnail: View {
    let isActive: Bool
    let isChecked: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            ThumbnailView(kind: .oasis)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(isActive ? Color(hex: 0x6F7DFF) : .clear, lineWidth: 3)
                }

            if isChecked {
                Circle()
                    .fill(Color(hex: 0x6F7DFF))
                    .frame(width: 20, height: 20)
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(.white)
                    }
                    .padding(5)
            } else {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(.white, lineWidth: 2)
                    .frame(width: 16, height: 16)
                    .background(.white.opacity(0.28), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .padding(6)
            }
        }
    }
}

private struct FileInfoGrid: View {
    private let rows = [
        ("Modified:", "16 Oct 2024"),
        ("Created:", "16 Oct 2024"),
        ("Size:", "168 MB"),
        ("File type:", "PNG")
    ]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 26, verticalSpacing: 14) {
            ForEach(rows, id: \.0) { row in
                GridRow {
                    Text(row.0)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.black.opacity(0.44))
                    Text(row.1)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.black.opacity(0.92))
                }
            }
        }
    }
}

private struct MyClutterBottomBar: View {
    var body: some View {
        HStack {
            Spacer()

            HStack(spacing: 12) {
                Text("16 Items Selected")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)

                Rectangle()
                    .fill(.black.opacity(0.2))
                    .frame(width: 1, height: 20)

                Text("1,7 GB")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.45))
            }

            Spacer()

            Button("Remove") {}
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .buttonStyle(.plain)
                .frame(width: 92, height: 44)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: 0x7B6DFF), Color(hex: 0x4B31C8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
        }
        .frame(height: 72)
        .padding(.horizontal, 16)
        .background(Color(hex: 0xF4F3F8))
    }
}

private struct ThumbnailView: View {
    let kind: ThumbnailKind

    var body: some View {
        switch kind {
        case .oasis:
            OasisPreview()
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        case .zip:
            ZStack {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color(hex: 0xF4F4F4))
                    .overlay {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .stroke(.black.opacity(0.06), lineWidth: 1)
                    }

                VStack(spacing: 2) {
                    Image(systemName: "zipper.page")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.black.opacity(0.42))
                    Text("ZIP")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(.black.opacity(0.32))
                }
            }
        case .people:
            ZStack {
                LinearGradient(colors: [Color(hex: 0xF3C1A4), Color(hex: 0x406D8D)], startPoint: .topLeading, endPoint: .bottomTrailing)
                HStack(spacing: -8) {
                    Circle().fill(Color(hex: 0x2B2B2F)).frame(width: 16, height: 16)
                    Circle().fill(Color(hex: 0xE7B08D)).frame(width: 17, height: 17)
                }
                .offset(y: 5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        }
    }
}

private struct OasisPreview: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(hex: 0xEEF2FF),
                        Color(hex: 0x7D98F6),
                        Color(hex: 0x3320A8)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Path { path in
                    path.move(to: CGPoint(x: proxy.size.width * 0.03, y: proxy.size.height * 0.92))
                    path.addCurve(
                        to: CGPoint(x: proxy.size.width * 0.46, y: proxy.size.height * 0.48),
                        control1: CGPoint(x: proxy.size.width * 0.17, y: proxy.size.height * 0.68),
                        control2: CGPoint(x: proxy.size.width * 0.27, y: proxy.size.height * 0.5)
                    )
                    path.addCurve(
                        to: CGPoint(x: proxy.size.width * 0.97, y: proxy.size.height * 0.86),
                        control1: CGPoint(x: proxy.size.width * 0.66, y: proxy.size.height * 0.46),
                        control2: CGPoint(x: proxy.size.width * 0.78, y: proxy.size.height * 0.78)
                    )
                    path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height))
                    path.addLine(to: CGPoint(x: 0, y: proxy.size.height))
                    path.closeSubpath()
                }
                .fill(Color(hex: 0x241572).opacity(0.8))

                Circle()
                    .fill(.white.opacity(0.82))
                    .frame(width: proxy.size.width * 0.28, height: proxy.size.width * 0.28)
                    .blur(radius: 2)
                    .offset(x: -proxy.size.width * 0.05, y: -proxy.size.height * 0.05)

                RoundedRectangle(cornerRadius: proxy.size.height * 0.16, style: .continuous)
                    .stroke(.white.opacity(0.92), lineWidth: max(proxy.size.width * 0.03, 2))
                    .frame(width: proxy.size.width * 0.66, height: proxy.size.height * 0.58)
                    .offset(x: -proxy.size.width * 0.14, y: -proxy.size.height * 0.04)

                ForEach(0..<10) { index in
                    Circle()
                        .fill(Color(hex: 0x7896FF).opacity(0.68))
                        .frame(width: max(proxy.size.width * 0.032, 3))
                        .offset(
                            x: CGFloat(index % 5) * proxy.size.width * 0.14 - proxy.size.width * 0.28,
                            y: CGFloat(index / 5) * proxy.size.height * 0.11 + proxy.size.height * 0.23
                        )
                }
            }
        }
    }
}

private struct MyClutterSidebar: View {
    private let items: [MyClutterSidebarItem] = [
        .smartCare,
        .cleanup,
        .protection,
        .performance,
        .applications,
        .myClutter
    ]

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
                .frame(height: 118)

            ForEach(items) { item in
                MyClutterSidebarIcon(item: item)
            }

            Spacer()

            ZStack {
                Circle()
                    .fill(.white.opacity(0.24))
                    .frame(width: 34, height: 34)

                Image(systemName: "circle.grid.cross.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.82), Color(hex: 0xDCE4FF).opacity(0.6))
            }
            .padding(.bottom, 42)
        }
        .frame(maxHeight: .infinity)
        .background {
            Rectangle()
                .fill(.white.opacity(0.03))
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(.white.opacity(0.06))
                        .frame(width: 1)
                }
        }
    }
}

private struct MyClutterSidebarIcon: View {
    let item: MyClutterSidebarItem

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(item == .myClutter ? .white.opacity(0.11) : .clear)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(item == .myClutter ? .white.opacity(0.16) : .clear, lineWidth: 1)
                }
                .frame(width: 58, height: 58)

            Image(systemName: item.symbolName)
                .font(.system(size: 23, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.9), Color(hex: 0x8EA8FF).opacity(item == .myClutter ? 0.95 : 0.46))
                .frame(width: 58, height: 58)

            if item == .myClutter {
                Circle()
                    .fill(.white.opacity(0.78))
                    .frame(width: 16, height: 16)
                    .shadow(color: .white.opacity(0.65), radius: 4)
                    .offset(x: 5, y: -5)
            }
        }
    }
}

private struct MyClutterBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: 0x2C1B86),
                    Color(hex: 0x5142C8),
                    Color(hex: 0x13084F)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color(hex: 0x6F7DFF).opacity(0.46),
                    .clear
                ],
                center: UnitPoint(x: 0.22, y: 0.42),
                startRadius: 10,
                endRadius: 520
            )

            LinearGradient(
                colors: [.black.opacity(0.02), .black.opacity(0.24)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private struct DuplicateFile: Identifiable {
    let id = UUID()
    let name: String
    let size: String
    let selected: Int
    let total: Int
    let thumbnail: ThumbnailKind
    let isSelected: Bool

    static let samples = [
        DuplicateFile(name: "oasis_.png", size: "1,2 GB", selected: 6, total: 7, thumbnail: .oasis, isSelected: true),
        DuplicateFile(name: "selfie_2024.zip", size: "841 MB", selected: 4, total: 5, thumbnail: .zip, isSelected: false),
        DuplicateFile(name: "wow.png", size: "21,8 MB", selected: 2, total: 3, thumbnail: .oasis, isSelected: false),
        DuplicateFile(name: "selfie_1.jpg", size: "15,3 MB", selected: 3, total: 4, thumbnail: .people, isSelected: false),
        DuplicateFile(name: "love.jpg", size: "1,6 MB", selected: 1, total: 2, thumbnail: .people, isSelected: false)
    ]
}

private enum ThumbnailKind {
    case oasis
    case zip
    case people
}

private enum MyClutterSidebarItem: String, Identifiable {
    case smartCare
    case cleanup
    case protection
    case performance
    case applications
    case myClutter

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .smartCare:
            "desktopcomputer"
        case .cleanup:
            "face.smiling.inverse"
        case .protection:
            "hand.raised.fill"
        case .performance:
            "bolt.fill"
        case .applications:
            "shippingbox.fill"
        case .myClutter:
            "folder.fill"
        }
    }
}

private extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

#Preview {
    MyClutterView()
        .frame(width: 1180, height: 760)
}
