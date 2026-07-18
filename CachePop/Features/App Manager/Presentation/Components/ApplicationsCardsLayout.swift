import SwiftUI

struct ApplicationsCardsLayout: View {
    var body: some View {
        HStack(spacing: 16) {
            ApplicationUpdateCard()
                .frame(width: 315)

            VStack(spacing: 16) {
                ApplicationWideCard(
                    title: "10 Unused Applications Found",
                    subtitle: "You may not need these apps, but they use 751 MB of space in total.",
                    accessory: .unused,
                    primaryButton: nil
                )
                .frame(height: 170)

                HStack(spacing: 16) {
                    ApplicationSmallCard(
                        title: "3 Unsupported\nApplications Found",
                        accessory: .unsupported,
                        primaryButton: "Uninstall"
                    )

                    ApplicationSmallCard(
                        title: "46,4 MB of App\nLeftovers Found",
                        accessory: .leftovers,
                        primaryButton: "Remove"
                    )
                }
                .frame(height: 170)
            }
        }
    }
}
