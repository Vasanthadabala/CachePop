//
//  JunkCleanerView.swift
//  CachePop
//
//  Created by Vasanth on 14/05/26.
//

import SwiftUI

struct JunkCleanerView: View {
    var onDone: () -> Void = {}

    @State private var viewModel = JunkCleanerViewModel()

    var body: some View {
        ZStack {
            CleanupBackground()

            switch viewModel.phase {
            case .intro:
                CleanupIntroContent(onScan: viewModel.startScan)
            case .scanning:
                CleanupScanningContent(
                    progress: viewModel.scanProgress,
                    currentPath: viewModel.currentPath,
                    onStartOver: viewModel.resetCleanup
                )
            case .found:
                CleanupFoundContent(
                    snapshot: viewModel.scanSnapshot,
                    onStartOver: viewModel.resetCleanup,
                    onClean: viewModel.finishCleaning
                )
            case .complete:
                ZStack(alignment: .top) {
                    CleanupTopBar(title: "Junk Cleaner", showsStartOver: true, onStartOver: viewModel.resetCleanup)

                    CleanupCompletePanel(cleanedSize: viewModel.scanSnapshot.formattedCacheSize, onDone: onDone)
                        .padding(.leading, 92)
                        .padding(.trailing, 82)
                        .padding(.top, 118)
                        .padding(.bottom, 82)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear {
            viewModel.cancel()
        }
    }
}

#Preview {
    JunkCleanerView()
        .frame(width: 1180, height: 760)
}
