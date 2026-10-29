import SwiftUI

struct ChatView: View {
    let conversation: Conversation
    let client: OrbitClient
    let endpoints: [ModelEndpoint]
    let onSelectEndpoint: (UUID) -> Void

    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var pendingUserText: String?
    @State private var streamedText = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.title).font(.headline)
                    Text(conversation.agentName).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
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
            }
            .defaultScrollAnchor(.bottom)
            OrbitComposer(text: $draft, isSending: isSending,
                          endpoints: endpoints, selectedEndpointID: conversation.endpointID,
                          focusID: conversation.id,
                          onSelectEndpoint: onSelectEndpoint, onSend: send)
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
