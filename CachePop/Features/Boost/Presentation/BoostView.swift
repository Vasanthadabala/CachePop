//
//  BoostView.swift
//  CachePop
//
//  Created by Vasanth on 14/05/26.
//

import SwiftUI

struct BoostView: View {
    var onDone: () -> Void = {}

    @State private var viewModel = BoostViewModel()

    var body: some View {
        ZStack {
            PerformanceBackground()

            if let reviewSection = viewModel.reviewSection {
                PerformanceManagerContent(
                    snapshot: viewModel.performanceSnapshot,
                    initialSection: reviewSection,
                    onBack: viewModel.hideReview
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(10)
            } else {
                switch viewModel.phase {
                case .intro:
                    PerformanceIntroContent(onScan: viewModel.startScan)
                case .scanning:
                    PerformanceScanningContent(
                        progress: viewModel.scanProgress,
                        currentPath: viewModel.currentPath,
                        onStop: viewModel.resetScan
                    )
                case .ready:
                    PerformanceReadyContent(
                        startupDetails: viewModel.startupDetails,
                        onStartOver: viewModel.resetScan,
                        onViewAllTasks: { viewModel.showReview(.loginItems) },
                        onReview: viewModel.showReview
                    )
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
    BoostView()
        .frame(width: 1180, height: 760)
}
