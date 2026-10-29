import SwiftUI

struct EndpointSettingsView: View {
    let client: OrbitClient
    let endpoints: [ModelEndpoint]
    let onCreated: (ModelEndpoint) -> Void

    @State private var provider = "openai"
    @State private var selectedProvider: String?
    @State private var customProtocol = "openai_compatible"
    @State private var customName = ""
    @State private var customKey = ""
    @State private var modelName = ""
    @State private var baseURL = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var openAIKey = ""
    @State private var hasOpenAIKey = false
    @State private var hasClaudeKey = false
    @State private var showDeleteKeyConfirmation = false
    @State private var keyMessage: String?
    @State private var connectionMessage: String?
    @State private var agentSettings: AgentSettings?
    @State private var agentName = "Orbit"
    @State private var agentInstructions = ""
    @State private var defaultEndpointID: UUID?
    @State private var showKeyEditor = false
    @State private var saveNotice: (title: String, detail: String)?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Image(systemName: "gearshape")
                    .font(.system(size: min(geometry.size.width * 0.36, 330), weight: .ultraLight))
                    .foregroundStyle(OrbitPalette.actionBlue.opacity(0.07))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(.trailing, 54)
                    .accessibilityHidden(true)

                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        if let selectedProvider {
                            Button {
                                withAnimation { self.selectedProvider = nil }
                                errorMessage = nil
                                connectionMessage = nil
                            } label: { Label("Impostazioni", systemImage: "chevron.left") }
                                .buttonStyle(.plain)
                                .foregroundStyle(OrbitPalette.actionBlue)
                            detailHeader(for: selectedProvider)
                            if selectedProvider == "agent" {
                                agentDetailSection
                            } else if selectedProvider == "openai" || selectedProvider == "anthropic" {
                                providerKeySection
                                modelSection
                            } else {
                                customSection
                            }
                            if let connectionMessage { Text(connectionMessage).foregroundStyle(.secondary) }
                        } else {
                            OrbitGradientTitle(text: "Impostazioni", size: 64)
                            agentOverviewSection
                            availableSection
                            sourceSection
                        }
                        if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                    }
                    .frame(maxWidth: 650, alignment: .leading)
                    .padding(36)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .background { OrbitAtmosphere() }
        .navigationTitle(selectedProvider == nil ? "Impostazioni" :
                         selectedProvider == "agent" ? "Agente" :
                         selectedProvider == "openai" ? "OpenAI API" :
                         selectedProvider == "anthropic" ? "Claude" : "Endpoint personalizzato")
        .onAppear { selectedProvider = nil }
        .task { await refreshKeyStatus() }
        .task { await loadAgentSettings() }
        .confirmationDialog("Rimuovere la chiave API dal Portachiavi?", isPresented: $showDeleteKeyConfirmation) {
            Button("Rimuovi chiave", role: .destructive) { deleteKey() }
        }
        .overlay {
            if let saveNotice {
                OrbitSaveConfirmation(title: saveNotice.title, detail: saveNotice.detail) {
                    withAnimation(.easeOut(duration: 0.18)) { self.saveNotice = nil }
                }
                .zIndex(1)
            }
        }
    }

    private var canAddModel: Bool {
        !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (provider == "openai" ? hasOpenAIKey : hasClaudeKey)
    }

    private var canSaveKey: Bool {
        !openAIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connessioni").font(.title2)
            providerRow("OpenAI API", subtitle: hasOpenAIKey ? "Chiave API pronta" : "Serve una chiave API",
                        symbol: "cloud.fill", color: .black, value: "openai")
            Divider()
            providerRow("Claude", subtitle: hasClaudeKey ? "Chiave API pronta" : "Serve una chiave API",
                        symbol: "sparkle", color: .orange, value: "anthropic")
            Divider()
            providerRow("Endpoint personalizzato", subtitle: "Un server tuo, anche con Ollama",
                        symbol: "network", color: .gray, value: "custom")
            Divider()
        }
    }

    private var agentOverviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Agente").font(.title2)
            providerRow(agentSettings?.name ?? "Orbit",
                        subtitle: "Nome, istruzioni e modello predefinito",
                        symbol: "sparkles", color: OrbitPalette.actionBlue, value: "agent")
            Divider()
        }
    }

    private var agentDetailSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            OrbitSettingsField("Nome dell’agente") {
                TextField("Orbit", text: $agentName)
                    .textFieldStyle(.plain)
            }
            OrbitSettingsField("Istruzioni", help: "Definiscono il modo in cui Orbit risponde nelle nuove chat.") {
                TextEditor(text: $agentInstructions)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.hidden)
                    .frame(minHeight: 140)
            }
            Button("Ripristina le istruzioni iniziali") {
                agentInstructions = OrbitAgentDefaults.instructions
            }
            .buttonStyle(.link)
            OrbitSettingsField("Modello predefinito", help: "Verrà usato nelle nuove chat.", surface: false) {
                Picker("Nuove chat", selection: $defaultEndpointID) {
                    ForEach(endpoints) { endpoint in
                        Text(endpoint.label).tag(Optional(endpoint.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            OrbitTextActionButton(title: "Salva agente", symbol: "checkmark",
                                  action: saveAgentSettings,
                                  ready: !agentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                      && defaultEndpointID != nil && !isSaving)
        }
    }

    private func detailHeader(for value: String) -> some View {
        let title = value == "agent" ? "Agente" :
                    value == "openai" ? "OpenAI API" :
                    value == "anthropic" ? "Claude" : "Endpoint personalizzato"
        return HStack(spacing: 16) {
            providerIcon(symbol: value == "anthropic" ? "sparkle" : value == "agent" ? "sparkles" : "network",
                         color: value == "anthropic" ? .orange : value == "agent" ? OrbitPalette.actionBlue : .gray,
                         value: value, size: 56)
            Text(title)
                .font(.system(size: value == "custom" ? 42 : 58, weight: .ultraLight))
                .minimumScaleFactor(0.8)
                .lineLimit(1)
        }
    }

    private func providerIcon(symbol: String, color: Color, value: String, size: CGFloat) -> some View {
        Group {
            if value == "agent", let url = Bundle.main.url(forResource: "OrbitAppIcon", withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: size, height: size)
            } else if value == "openai", let url = Bundle.main.url(forResource: "OpenAI", withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.24))
            } else {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.47, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(color, in: RoundedRectangle(cornerRadius: size * 0.24))
            }
        }
        .accessibilityHidden(true)
    }

    private func providerRow(_ title: String, subtitle: String, symbol: String,
                             color: Color, value: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedProvider = value
                provider = value
                modelName = ""
                openAIKey = ""
                showKeyEditor = false
                keyMessage = nil
                connectionMessage = nil
                if value == "custom" { baseURL = ""; customProtocol = "openai_compatible" }
                if value == "agent", let settings = agentSettings {
                    agentName = settings.name
                    agentInstructions = settings.instructions
                    defaultEndpointID = settings.defaultEndpointID
                }
            }
        } label: {
            HStack(spacing: 12) {
                providerIcon(symbol: symbol, color: color, value: value, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Configura \(title)")
    }

    private var providerKeySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Chiave API").font(.title2)
            Text(provider == "openai"
                 ? "L’API OpenAI usa una chiave separata dall’abbonamento ChatGPT."
                 : "La chiave Claude si crea nella Console Anthropic.")
                .foregroundStyle(.secondary)
            Label(currentKeyReady ? "Chiave salvata nel Portachiavi" : "Aggiungi una chiave API",
                  systemImage: currentKeyReady ? "checkmark.circle.fill" : "key.horizontal")
                .foregroundStyle(currentKeyReady ? .green : .secondary)
            if !currentKeyReady || showKeyEditor {
                OrbitSettingsField("Chiave API", help: "La chiave viene conservata nel Portachiavi del Mac.") {
                    SecureField("Incolla la chiave API", text: $openAIKey)
                        .textFieldStyle(.plain)
                        .textContentType(.password)
                }
                OrbitTextActionButton(title: "Salva chiave", symbol: "checkmark", action: saveKey,
                                      ready: canSaveKey && !isSaving)
            } else {
                Button("Cambia o rimuovi la chiave") { showKeyEditor = true }
                    .buttonStyle(.link)
            }
            if currentKeyReady && showKeyEditor {
                Button("Rimuovi chiave", role: .destructive) {
                    showDeleteKeyConfirmation = true
                }
                .buttonStyle(.link)
            }
            if let keyMessage { Text(keyMessage).foregroundStyle(.secondary) }
        }
    }

    private var customSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Collega un server o un modello sul Mac.").foregroundStyle(.secondary)
            OrbitSettingsField("Nome della connessione") {
                TextField("Per esempio: Modello sul Mac", text: $customName)
                    .textFieldStyle(.plain)
            }
            OrbitSettingsField("Formato API", surface: false) {
                Picker("Formato API", selection: $customProtocol) {
                    Text("OpenAI compatibile").tag("openai_compatible")
                    Text("Ollama").tag("ollama")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .onChange(of: customProtocol) { _, newValue in
                    baseURL = newValue == "ollama" ? "http://127.0.0.1:11434" : ""
                }
            }
            OrbitSettingsField("Indirizzo del server", help: customProtocol == "ollama"
                               ? "Per Ollama su questo Mac: http://127.0.0.1:11434"
                               : "Indica l’indirizzo base, per esempio https://server.example/v1") {
                TextField("https://server.example/v1", text: $baseURL)
                    .textFieldStyle(.plain)
                    .textContentType(.URL)
            }
            OrbitSettingsField("Nome del modello") {
                TextField("Per esempio: llama3.2", text: $modelName)
                    .textFieldStyle(.plain)
            }
            if customProtocol == "openai_compatible" {
                OrbitSettingsField("Chiave API", help: "Facoltativa, se il server la richiede.") {
                    SecureField("Chiave API", text: $customKey)
                        .textFieldStyle(.plain)
                }
            }
            OrbitTextActionButton(title: "Aggiungi connessione", symbol: "plus", action: saveEndpoint,
                                  ready: canAddCustom && !isSaving)
        }
    }

    private var canAddCustom: Bool {
        !customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var currentKeyReady: Bool { provider == "openai" ? hasOpenAIKey : hasClaudeKey }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Aggiungi un modello").font(.title2)
            OrbitSettingsField("Nome del modello") {
                TextField(provider == "openai" ? "Per esempio: gpt-4.1" : "Per esempio: claude-sonnet-4-5",
                          text: $modelName)
                    .textFieldStyle(.plain)
            }
            OrbitTextActionButton(title: "Aggiungi modello", symbol: "plus", action: saveEndpoint,
                                  ready: canAddModel && !isSaving)
        }
    }

    private var availableSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Modelli disponibili").font(.title2)
            ForEach(endpoints) { endpoint in
                HStack(spacing: 10) {
                    Image(systemName: endpoint.isLocal ? "desktopcomputer" : "cloud")
                        .foregroundStyle(OrbitPalette.actionBlue)
                    Text(endpoint.label)
                    Spacer()
                    Text(endpoint.provider == "demo" ? "Demo" : (endpoint.isLocal ? "Sul Mac" : "Online"))
                        .foregroundStyle(.secondary)
                }
                Divider()
            }
        }
    }

    private func saveEndpoint() {
        guard (selectedProvider == "custom" ? canAddCustom : canAddModel) else {
            errorMessage = "Completa i campi richiesti prima di aggiungere la connessione."
            return
        }
        let targetProvider = selectedProvider == "custom" ? customProtocol : provider
        let displayName = selectedProvider == "custom" ? customName : "\(provider == "openai" ? "OpenAI" : "Claude") · \(modelName)"
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let endpoint = try await client.createEndpoint(NewEndpoint(
                    label: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                    provider: targetProvider,
                    modelName: modelName.trimmingCharacters(in: .whitespacesAndNewlines),
                    baseURL: selectedProvider == "custom" ? baseURL.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                    apiKey: selectedProvider == "custom" && customProtocol == "openai_compatible"
                        ? (customKey.isEmpty ? nil : customKey) : nil
                ))
                onCreated(endpoint)
                modelName = ""
                customName = ""
                customKey = ""
                errorMessage = nil
                connectionMessage = nil
                withAnimation(.easeOut(duration: 0.18)) {
                    saveNotice = ("Connessione aggiunta", "Il modello è pronto per essere scelto nelle chat.")
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func refreshKeyStatus() async {
        do {
            hasOpenAIKey = try await client.keyStatus(for: "openai").configured
            hasClaudeKey = try await client.keyStatus(for: "anthropic").configured
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveKey() {
        guard canSaveKey else {
            keyMessage = "Inserisci la chiave API prima di salvarla."
            return
        }
        let value = openAIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let configured = try await client.saveKey(value, for: provider).configured
                if provider == "openai" { hasOpenAIKey = configured }
                else { hasClaudeKey = configured }
                openAIKey = ""
                keyMessage = nil
                showKeyEditor = false
                errorMessage = nil
                withAnimation(.easeOut(duration: 0.18)) {
                    saveNotice = ("Chiave salvata", "La chiave API è custodita nel Portachiavi del Mac.")
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deleteKey() {
        Task {
            do {
                let configured = try await client.deleteKey(for: provider).configured
                if provider == "openai" { hasOpenAIKey = configured }
                else { hasClaudeKey = configured }
                openAIKey = ""
                keyMessage = "Chiave rimossa dal Portachiavi."
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadAgentSettings() async {
        do {
            let settings = try await client.agentSettings()
            agentSettings = settings
            agentName = settings.name
            agentInstructions = settings.instructions
            defaultEndpointID = settings.defaultEndpointID
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveAgentSettings() {
        guard let defaultEndpointID else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let saved = try await client.saveAgentSettings(AgentSettings(
                    name: agentName.trimmingCharacters(in: .whitespacesAndNewlines),
                    instructions: agentInstructions,
                    defaultEndpointID: defaultEndpointID
                ))
                agentSettings = saved
                connectionMessage = nil
                errorMessage = nil
                withAnimation(.easeOut(duration: 0.18)) {
                    saveNotice = ("Agente aggiornato", "Le nuove chat useranno queste impostazioni.")
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

enum OrbitAgentDefaults {
    static let instructions = "Sei Orbit, un assistente personale. Rispondi nella lingua dell’utente con chiarezza e accuratezza. Se non conosci una risposta, dillo apertamente."
}
