import SwiftUI

struct ChatView: View {
    let conversation: Conversation
    let client: OrbitClient
    let endpoints: [ModelEndpoint]
    let onSelectEndpoint: (UUID) -> Void
    let onSelectAccessMode: (String) -> Void
    let onTitleUpdated: (String) -> Void

    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var pendingUserText: String?
    @State private var streamedText = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(conversation.title)
                    .font(.system(size: 23, weight: .light))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if messages.isEmpty && pendingUserText == nil {
                        VStack(spacing: 10) {
                            OrbitWordmark(size: 52)
                            OrbitWave(height: 125)
                            Text("Come posso aiutarti?")
                                .font(.title2.weight(.light))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 70)
                    }
                    ForEach(messages) { message in
                        OrbitMessageRow(role: message.role, content: message.content,
                                        agentName: conversation.agentName)
                    }
                    if let pendingUserText {
                        OrbitMessageRow(role: "user", content: pendingUserText,
                                        agentName: conversation.agentName)
                    }
                    if isSending || !streamedText.isEmpty {
                        OrbitMessageRow(role: "assistant", content: streamedText.isEmpty ? "…" : streamedText,
                                        agentName: conversation.agentName)
                    }
                }
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
                .padding(28)
                .background(OrbitOverlayScrollStyle())
            }
            .defaultScrollAnchor(.bottom)
            OrbitComposer(text: $draft, isSending: isSending,
                          endpoints: endpoints, selectedEndpointID: conversation.endpointID,
                          accessMode: conversation.accessMode,
                          focusID: conversation.id,
                          onSelectEndpoint: onSelectEndpoint,
                          onSelectAccessMode: onSelectAccessMode, onSend: send)
                .frame(maxWidth: 820)
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
        }
        .background { OrbitAtmosphere() }
        .task(id: conversation.id) { await loadMessages() }
        .alert("Errore", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func loadMessages() async {
        do {
            messages = try await client.listMessages(in: conversation.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func send() {
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !isSending else { return }
        draft = ""
        pendingUserText = content
        streamedText = ""
        isSending = true
        Task {
            defer { isSending = false }
            do {
                for try await event in client.sendMessage(content, in: conversation.id) {
                    switch event {
                    case .title(let title): onTitleUpdated(title)
                    case .delta(let text): streamedText += text
                    case .completed: break
                    case .failed(let message): errorMessage = message
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            await loadMessages()
            pendingUserText = nil
            streamedText = ""
        }
    }
}
