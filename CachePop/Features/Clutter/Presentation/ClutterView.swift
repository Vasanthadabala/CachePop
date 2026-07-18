//
//  ClutterView.swift
//  CachePop
//
//  Created by Vasanth on 14/05/26.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ClutterView: View {
    var onBack: () -> Void = {}
    @State private var viewModel = ClutterViewModel()

    var body: some View {
        Group {
            switch viewModel.phase {
            case .welcome:
                ClutterWelcomeContent(
                    selectedFolder: $viewModel.selectedFolder,
                    onScan: viewModel.startScan
                )
            case .scanning:
                ClutterScanningContent(
                    folder: viewModel.selectedFolder,
                    currentPath: viewModel.scanningPath,
                    onStop: viewModel.stopScan
                )
            case .summary:
                ClutterResultsSummaryContent(
                    result: viewModel.scannedResult ?? .empty,
                    onStartOver: viewModel.resetToWelcome,
                    onReview: viewModel.reviewTarget
                )
            case .manager:
                ClutterManagerContent(
                    onBack: viewModel.goBackToSummary,
                    result: viewModel.scannedResult,
                    reviewTarget: viewModel.reviewTarget,
                    duplicateSelectionsByGroupID: $viewModel.duplicateSelectionsByGroupID
                )
            }
        }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.top, 10)
            .padding(.trailing, 10)
            .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear {
            viewModel.cancel()
        }
    }
}

