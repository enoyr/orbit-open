import SwiftUI

struct OrbitMessageRow: View {
    let role: String
    let content: String
    var agentName = "Orbit"

    var body: some View {
        HStack(alignment: .top) {
            if role == "user" { Spacer(minLength: 70) }
            VStack(alignment: .leading, spacing: 9) {
                OrbitMarkdownMessage(content: content)
                HStack {
                    OrbitCopyButton(text: content, label: "Copia messaggio")
                    Spacer(minLength: 0)
                }
            }
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
                .background(
                    role == "user" ? OrbitPalette.blue.opacity(0.12) : Color.secondary.opacity(0.075),
                    in: RoundedRectangle(cornerRadius: 18)
                )
            if role != "user" { Spacer(minLength: 70) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(role == "user" ? "Tu" : agentName): \(content)")
    }
}

struct OrbitComposer: View {
    @Binding var text: String
    let isSending: Bool
    let endpoints: [ModelEndpoint]
    let selectedEndpointID: UUID
    let accessMode: String
    let focusID: UUID
    let onSelectEndpoint: (UUID) -> Void
    let onSelectAccessMode: (String) -> Void
    let onSend: () -> Void
    @State private var pendingFeature: String?
    @State private var inputHeight: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack(alignment: .topLeading) {
                OrbitComposerInput(text: $text, height: $inputHeight,
                                   focusID: focusID, onSend: onSend)
                    .frame(height: inputHeight)
                if text.isEmpty {
                    Text("Scrivi o chiedi qualcosa…")
                        .font(.system(size: 17))
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
            .accessibilityLabel("Messaggio")
            HStack(spacing: 16) {
                Button { pendingFeature = "Allegati" } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .regular))
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel("Aggiungi allegato")
                Menu {
                    Button("Richiedi approvazione", systemImage: accessMode == "approval_required" ? "checkmark" : "hand.raised") {
                        onSelectAccessMode("approval_required")
                    }
                    Button("Accesso completo", systemImage: accessMode == "full_access" ? "checkmark" : "bolt") {
                        onSelectAccessMode("full_access")
                    }
                } label: {
                    Label(accessMode == "full_access" ? "Accesso completo" : "Richiedi approvazione",
                          systemImage: accessMode == "full_access" ? "bolt" : "hand.raised")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .help("Preferenza per le future azioni su file e applicazioni")
                Spacer(minLength: 8)
                modelMenu
                Button { pendingFeature = "Voce" } label: {
                    Image(systemName: "mic")
                        .font(.system(size: 20))
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel("Dettatura vocale")
                sendButton
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.96),
                    in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28)
            .strokeBorder(Color.primary.opacity(0.075), lineWidth: 1))
        .shadow(color: .black.opacity(0.055), radius: 15, y: 5)
        .popover(isPresented: Binding(
            get: { pendingFeature != nil },
            set: { if !$0 { pendingFeature = nil } }
        )) {
            Text("\(pendingFeature ?? "Funzione") in preparazione")
                .padding(18)
        }
    }

    private var modelMenu: some View {
        Menu {
            ForEach(endpoints) { endpoint in
                Button {
                    onSelectEndpoint(endpoint.id)
                } label: {
                    if endpoint.id == selectedEndpointID {
                        Label(endpoint.label, systemImage: "checkmark")
                    } else {
                        Text(endpoint.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                Text(endpoints.first(where: { $0.id == selectedEndpointID })?.label ?? "Modello")
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 14))
        }
        .buttonStyle(.plain)
        .disabled(isSending)
        .accessibilityLabel("Scegli modello")
    }

    private var sendButton: some View {
        Button(action: onSend) {
            Image(systemName: "arrow.up")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(OrbitPalette.actionBlue.opacity(canSend ? 1 : 0.42), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .accessibilityLabel("Invia messaggio")
    }

    private var canSend: Bool {
        !isSending && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
