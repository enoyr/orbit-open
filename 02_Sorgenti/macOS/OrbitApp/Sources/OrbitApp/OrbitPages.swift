import SwiftUI

struct OrbitHomeView: View {
    let onNewChat: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                        OrbitWordmark(size: 64)
                        OrbitWave(height: 210)
                            .padding(.horizontal, -36)
                        if geometry.size.width >= OrbitLayout.homeActionStackWidth {
                            HStack(alignment: .firstTextBaseline, spacing: 36) {
                                homeQuestion
                                newChatAction
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                homeQuestion
                                newChatAction
                            }
                        }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.horizontal, 28)
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height, alignment: .center)
            }
        }
        .background { OrbitAtmosphere() }
    }

    private var homeQuestion: some View {
        Text("Cosa vuoi fare oggi?")
            .font(.system(size: 26, weight: .regular, design: .rounded))
            .foregroundStyle(.primary)
    }

    private var newChatAction: some View {
        OrbitTextActionButton(title: "Nuova chat", symbol: "plus", action: onNewChat)
    }
}

struct OrbitFuturePage: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Image(systemName: symbol)
                    .font(.system(size: min(geometry.size.width * 0.36, 330), weight: .ultraLight))
                    .foregroundStyle(OrbitPalette.actionBlue.opacity(0.09))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(.trailing, 54)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 0) {
                    OrbitGradientTitle(text: title, size: 64)
                    Spacer(minLength: 100)
                    Text(subtitle)
                        .font(.system(size: 26, weight: .regular, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("In preparazione")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(.top, 12)
            }
                .padding(36)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .background { OrbitAtmosphere() }
    }
}
