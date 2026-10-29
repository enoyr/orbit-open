import SwiftUI
import AppKit

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
    @State private var pendingFileName: String?
    @State private var streamedText = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var previewFile: OrbitLocalFile?
    @State private var attachedFile: OrbitLocalFile?
    @State private var isFilePanelOpen = false
    @State private var isFileApprovalShown = false

    var body: some View {
        GeometryReader { geometry in
            Group {
                if isFilePanelOpen, let previewFile, geometry.size.width >= 760 {
                    HSplitView {
                        chatContent.frame(minWidth: 420)
                        OrbitFilePanel(file: previewFile) { isFilePanelOpen = false }
                    }
                } else {
                    ZStack {
                        chatContent
                        if isFilePanelOpen, let previewFile {
                            OrbitFilePanel(file: previewFile) { isFilePanelOpen = false }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
            }
        }
        .task(id: conversation.id) { await loadMessages() }
        .onChange(of: conversation.id) { _, _ in
            messages = []
            previewFile = nil
            attachedFile = nil
            isFilePanelOpen = false
        }
        .alert("Inviare il file al modello?", isPresented: $isFileApprovalShown) {
            Button("Invia file e messaggio") {
                sendApprovedMessage(draft.trimmingCharacters(in: .whitespacesAndNewlines), fileApproved: true)
            }
            Button("Annulla", role: .cancel) { }
        } message: {
            Text("Il contenuto dei file presenti in questa chat sarà usato dalla connessione scelta per rispondere.")
        }
        .alert("Errore", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var chatContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text(conversation.title)
                    .font(.system(size: 23, weight: .light))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if previewFile != nil && !isFilePanelOpen {
                    Button { isFilePanelOpen = true } label: {
                        Image(systemName: "sidebar.right")
                    }
                    .buttonStyle(.plain)
                    .help("Mostra il file")
                }
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
                                        agentName: conversation.agentName, fileName: message.fileName,
                                        onOpenFile: message.fileName == nil ? nil : {
                                            openStoredFile(message.id)
                                        })
                    }
                    if let pendingUserText {
                        OrbitMessageRow(role: "user", content: pendingUserText,
                                        agentName: conversation.agentName, fileName: pendingFileName)
                    }
                    if isSending && streamedText.isEmpty {
                        OrbitResponseStatus(text: "Orbit sta preparando la risposta…")
                    }
                    if !streamedText.isEmpty {
                        OrbitMessageRow(role: "assistant", content: streamedText,
                                        agentName: conversation.agentName)
                        if isSending {
                            OrbitResponseStatus(text: "Orbit sta scrivendo…")
                        }
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
                          onSelectAccessMode: onSelectAccessMode, onSend: send,
                          attachedFileName: attachedFile?.name,
                          onAddFile: chooseFile,
                          onRemoveFile: { attachedFile = nil })
                .frame(maxWidth: 820)
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
        }
        .background { OrbitAtmosphere() }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "Scegli un file per Orbit"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let file = try OrbitLocalFile.load(url)
            previewFile = file
            attachedFile = file
            isFilePanelOpen = true
            if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft = "Riassumi questo file."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openStoredFile(_ messageID: UUID) {
        Task {
            do {
                let stored = try await client.filePreview(in: conversation.id, messageID: messageID)
                previewFile = OrbitLocalFile(name: stored.name, content: stored.content,
                                             wasTruncated: false)
                isFilePanelOpen = true
            } catch {
                errorMessage = error.localizedDescription
            }
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
        if (attachedFile != nil || messages.contains(where: { $0.fileName != nil }))
            && conversation.accessMode == "approval_required" {
            isFileApprovalShown = true
            return
        }
        sendApprovedMessage(content, fileApproved: false)
    }

    private func sendApprovedMessage(_ content: String, fileApproved: Bool) {
        guard !content.isEmpty, !isSending else { return }
        let file = attachedFile
        draft = ""
        attachedFile = nil
        pendingUserText = content
        pendingFileName = file?.name
        streamedText = ""
        isSending = true
        Task {
            defer { isSending = false }
            do {
                for try await event in client.sendMessage(content, in: conversation.id,
                                                          fileName: file?.name, fileContent: file?.content,
                                                          fileApproved: fileApproved) {
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
            pendingFileName = nil
            streamedText = ""
        }
    }
}
