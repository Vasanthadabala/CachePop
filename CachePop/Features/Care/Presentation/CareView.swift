//
//  CareView.swift
//  CachePop
//
//  Created by Vasanth on 13/05/26.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CareView: View {
    @State private var viewModel = CareViewModel()
    @State private var pulse = false

    var body: some View {
        ZStack {
            AppTheme.Colors.appBackground
                .ignoresSafeArea()

            GeometryReader { proxy in
                let scale = min(max(proxy.size.width / 1180, 0.78), 1.08)

                ZStack(alignment: .topLeading) {
                    CareSectionBackground(selectedItem: viewModel.selectedItem)

                    if let activeDetail = viewModel.activeDetail {
                        HStack(spacing: 0) {
                            CareSidebar(selectedItem: $viewModel.selectedItem)
                                .frame(width: 250)
                                .clipped()

                            CareLogDetailContent(
                                detail: activeDetail,
                                onBack: { viewModel.hideActiveDetail() }
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    } else {
                        HStack(spacing: 0) {
                            CareSidebar(selectedItem: $viewModel.selectedItem)
                                .frame(width: 250)

                            Group {
                                if viewModel.selectedItem == .smartCare, viewModel.scanPhase == .complete {
                                    CareResultsContent(
                                        snapshot: viewModel.scanSnapshot,
                                        onViewLog: { viewModel.showLog(.all, cleaned: true) },
                                        onStartOver: viewModel.resetScan
                                    )
                                } else if viewModel.selectedItem == .smartCare, viewModel.scanPhase == .readyToRun {
                                    CareReadyToRunContent(
                                        snapshot: viewModel.scanSnapshot,
                                        pulse: pulse,
                                        onStartOver: viewModel.resetScan,
                                        onReview: { viewModel.showLog($0, cleaned: false) },
                                        onRun: viewModel.runReadyTasks
                                    )
                                } else if viewModel.selectedItem == .smartCare, viewModel.scanPhase == .cleaning {
                                    CareCleaningContent(
                                        progress: viewModel.cleaningProgress,
                                        snapshot: viewModel.scanSnapshot,
                                        pulse: pulse
                                    )
                                } else if viewModel.selectedItem == .smartCare, viewModel.scanPhase == .scanning {
                                    CareScanningContent(
                                        scanProgress: viewModel.scanProgress,
                                        snapshot: viewModel.scanSnapshot,
                                        pulse: pulse,
                                        onStop: viewModel.resetScan
                                    )
                                } else if viewModel.selectedItem == .cleanup {
                                    JunkCleanerView {
                                        viewModel.selectSidebarItem(.smartCare)
                                    }
                                } else if viewModel.selectedItem == .performance {
                                    BoostView {
                                        viewModel.selectSidebarItem(.smartCare)
                                    }
                                } else if viewModel.selectedItem == .applications {
                                    AppManagerView {
                                        viewModel.selectSidebarItem(.smartCare)
                                    }
                                } else if viewModel.selectedItem == .myClutter {
                                    ClutterView {
                                        viewModel.selectSidebarItem(.smartCare)
                                    }
                                } else if viewModel.selectedItem == .assistant {
                                    AssistantView()
                                } else {
                                    CareHomeContent(
                                        snapshot: viewModel.scanSnapshot,
                                        scale: scale,
                                        onScan: viewModel.startScan,
                                        onSelectFeature: viewModel.selectSidebarItem
                                    )
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 980, minHeight: 760)
        .background(AppTheme.Colors.appBackground)
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .onDisappear {
            viewModel.cancel()
        }
    }
}
