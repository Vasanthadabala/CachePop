//
//  AssistantView.swift
//  CachePop
//
//  Created by Vasanth on 14/05/26.
//

import SwiftUI

struct AssistantView: View {
    var body: some View {
        VStack(spacing: 0) {
            Text("Assistant")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.68))
                .padding(.top, 26)

            HStack(spacing: 16) {
                MacHealthPanel()
                    .frame(maxWidth: .infinity)

                AssistantTipsPane()
                    .frame(width: 405)
            }
            .padding(.top, 24)
            .padding(.trailing, 24)
            .padding(.bottom, 24)
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    AssistantView()
        .frame(width: 1180, height: 760)
}
