//
//  AppManagerView.swift
//  CachePop
//
//  Created by Vasanth on 14/05/26.
//

import SwiftUI

struct AppManagerView: View {
    var onStartOver: () -> Void = {}
    
    @State private var viewModel = AppManagerViewModel()

    var body: some View {
        VStack(spacing: 0) {
            ApplicationsTopBar(onStartOver: onStartOver)

            VStack(spacing: 22) {
                Text("We've found \(viewModel.totalAppsFound) apps on your Mac.")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Button("Manage My Applications") {
                    viewModel.scanApplications()
                }
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .buttonStyle(.appInteractive)
                    .padding(.horizontal, 24)
                    .frame(height: 42)
                    .background {
                        Capsule(style: .continuous)
                            .fill(FeatureAccent.appManager.gradient)
                    }
                    .accentGlow(.appManager, radius: 12, y: 5)
                    .raisedButtonChrome(cornerRadius: 21)
            }
            .padding(.top, 88)

            Spacer(minLength: 76)

            ApplicationsCardsLayout()
                .padding(.leading, 28)
                .padding(.trailing, 24)
                .padding(.bottom, 46)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            viewModel.scanApplications()
        }
    }
}

#Preview {
    AppManagerView()
        .frame(width: 1180, height: 760)
}
