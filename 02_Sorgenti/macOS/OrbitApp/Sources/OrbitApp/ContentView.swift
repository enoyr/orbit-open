import SwiftUI

private enum OrbitDestination: Hashable {
    case home
    case conversation(UUID)
    case library
    case activity
    case settings
}

struct ContentView: View {
    let client: OrbitClient

    @State private var conversations: [Conversation] = []
    @State private var endpoints: [ModelEndpoint] = []
    @State private var selection: OrbitDestination? = .home
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var conversationToDelete: Conversation?
    @State private var conversationToRename: Conversation?
    @State private var renameDraft = ""
    @State private var sidebarVisible = true
    @State private var isCompact = false

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < OrbitLayout.sidebarCollapseWidth
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    if !compact && sidebarVisible { sidebar }
                    detail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if compact && sidebarVisible {
                    Color.black.opacity(0.08)
                        .ignoresSafeArea()
                        .onTapGesture { withAnimation { sidebarVisible = false } }
                    sidebar
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .onAppear {
                isCompact = compact
                if compact { sidebarVisible = false }
            }
            .onChange(of: compact) { _, newValue in
                isCompact = newValue
                withAnimation { sidebarVisible = !newValue }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(detailTitle)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { sidebarVisible.toggle() }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help(sidebarVisible ? "Nascondi barra laterale" : "Mostra barra laterale")
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: createConversation) { Image(systemName: "square.and.pencil") }
                    .help("Nuova chat")
                    .disabled(isLoading)
            }
        }
        .tint(Color.accentColor)
        .task { await loadData() }
        .alert("Errore", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Eliminare questa chat?", isPresented: Binding(
            get: { conversationToDelete != nil },
            set: { if !$0 { conversationToDelete = nil } }
        )) {
            Button("Elimina chat", role: .destructive) { deletePendingConversation() }
            Button("Annulla", role: .cancel) { conversationToDelete = nil }
        } message: {
            Text("La conversazione e i suoi messaggi verranno eliminati dal Mac.")
        }
        .alert("Rinomina chat", isPresented: Binding(
            get: { conversationToRename != nil },
            set: { if !$0 { conversationToRename = nil } }
        )) {
            TextField("Nome della chat", text: $renameDraft)
            Button("Salva") { renamePendingConversation() }
            Button("Annulla", role: .cancel) { conversationToRename = nil }
        } message: {
            Text("Il nuovo nome comparirà nella barra laterale.")
        }
    }

    private var sidebar: some View {
            VStack(alignment: .leading, spacing: 14) {
                OrbitWordmark(size: 32)
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        sidebarRow("Inizio", symbol: "house", destination: .home)
                        sidebarRow("Libreria", symbol: "books.vertical", destination: .library)
                        sidebarRow("Attività", symbol: "waveform.path", destination: .activity)
                        if !conversations.isEmpty {
                            Text("Recenti")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.top, 20)
                                .padding(.bottom, 4)
                        }
                        ForEach(conversations) { conversation in
                            OrbitConversationSidebarRow(
                                title: conversation.title,
                                selected: selection == .conversation(conversation.id),
                                alwaysShowActions: isCompact,
                                onSelect: {
                                    selection = .conversation(conversation.id)
                                    if isCompact { withAnimation { sidebarVisible = false } }
                                },
                                onRename: { beginRename(conversation) },
                                onDelete: { conversationToDelete = conversation }
                            )
                        }
                        Divider().padding(.vertical, 12)
                        sidebarRow("Impostazioni", symbol: "gearshape", destination: .settings)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .background(OrbitOverlayScrollStyle())
                }
            }
            .frame(width: 250)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.5), lineWidth: 1))
            .shadow(color: .black.opacity(0.09), radius: 20, x: 5, y: 8)
            .padding(12)
    }

    private func sidebarRow(_ title: String, symbol: String,
                            destination: OrbitDestination) -> some View {
        OrbitSidebarRow(title: title, symbol: symbol,
                        selected: selection == destination) {
            selection = destination
            if isCompact { withAnimation { sidebarVisible = false } }
        }
    }

    private var detailTitle: String {
        switch selection ?? .home {
        case .home: "Inizio"
        case .conversation: ""
        case .library: "Libreria"
        case .activity: "Attività"
        case .settings: "Impostazioni"
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .home {
        case .home:
            OrbitHomeView(onNewChat: createConversation)
        case .conversation(let id):
            if let conversation = conversations.first(where: { $0.id == id }) {
                ChatView(
                    conversation: conversation,
                    client: client,
                    endpoints: endpoints,
                    onSelectEndpoint: { endpointID in selectEndpoint(endpointID, for: id) },
                    onSelectAccessMode: { mode in selectAccessMode(mode, for: id) },
                    onTitleUpdated: { title in updateTitle(title, for: id) }
                )
            } else {
                OrbitHomeView(onNewChat: createConversation)
            }
        case .library:
            OrbitFuturePage(
                title: "Libreria",
                subtitle: "I tuoi contenuti, in un solo posto.",
                symbol: "books.vertical"
            )
        case .activity:
            OrbitFuturePage(
                title: "Attività",
                subtitle: "Il lavoro di Orbit, a colpo d’occhio.",
                symbol: "waveform.path"
            )
        case .settings:
            EndpointSettingsView(client: client, endpoints: endpoints) { endpoint in
                endpoints.append(endpoint)
            }
        }
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }
        do {
            conversations = try await client.listConversations()
            endpoints = try await client.listEndpoints()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func selectEndpoint(_ endpointID: UUID, for conversationID: UUID) {
        Task {
            do {
                let updated = try await client.selectEndpoint(endpointID, for: conversationID)
                if let index = conversations.firstIndex(where: { $0.id == conversationID }) {
                    conversations[index] = updated
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func selectAccessMode(_ mode: String, for conversationID: UUID) {
        Task {
            do {
                let updated = try await client.selectAccessMode(mode, for: conversationID)
                if let index = conversations.firstIndex(where: { $0.id == conversationID }) {
                    conversations[index] = updated
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func updateTitle(_ title: String, for conversationID: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        var updated = conversations.remove(at: index)
        updated.title = title
        conversations.insert(updated, at: 0)
    }

    private func createConversation() {
        Task {
            isLoading = true
            defer { isLoading = false }
            do {
                let conversation = try await client.createConversation()
                conversations.insert(conversation, at: 0)
                selection = .conversation(conversation.id)
                if isCompact { sidebarVisible = false }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deletePendingConversation() {
        guard let conversation = conversationToDelete else { return }
        conversationToDelete = nil
        Task {
            do {
                try await client.deleteConversation(conversation.id)
                conversations.removeAll { $0.id == conversation.id }
                if selection == .conversation(conversation.id) { selection = .home }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func beginRename(_ conversation: Conversation) {
        renameDraft = conversation.title
        conversationToRename = conversation
    }

    private func renamePendingConversation() {
        guard let conversation = conversationToRename else { return }
        let title = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        conversationToRename = nil
        guard !title.isEmpty else { return }
        Task {
            do {
                let updated = try await client.renameConversation(conversation.id, to: title)
                if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
                    conversations[index] = updated
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
