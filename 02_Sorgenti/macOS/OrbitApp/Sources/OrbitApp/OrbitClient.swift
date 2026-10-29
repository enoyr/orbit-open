import Foundation

struct Conversation: Decodable, Identifiable, Hashable {
    let id: UUID
    var title: String
    let endpointID: UUID
    let agentName: String
    let accessMode: String
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title
        case endpointID = "endpoint_id"
        case agentName = "agent_name"
        case accessMode = "access_mode"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct AgentSettings: Codable {
    var name: String
    var instructions: String
    var defaultEndpointID: UUID

    enum CodingKeys: String, CodingKey {
        case name, instructions
        case defaultEndpointID = "default_endpoint_id"
    }
}

struct ModelEndpoint: Decodable, Identifiable, Hashable {
    let id: UUID
    let label: String
    let provider: String
    let modelName: String
    let baseURL: String?
    let isLocal: Bool
    let enabled: Bool

    enum CodingKeys: String, CodingKey {
        case id, label, provider, enabled
        case modelName = "model_name"
        case baseURL = "base_url"
        case isLocal = "is_local"
    }
}

struct NewEndpoint: Encodable {
    let label: String
    let provider: String
    let modelName: String
    let baseURL: String?
    let apiKey: String?

    enum CodingKeys: String, CodingKey {
        case label, provider
        case modelName = "model_name"
        case baseURL = "base_url"
        case apiKey = "api_key"
    }
}

private struct EndpointSelection: Encodable {
    let endpointID: UUID

    enum CodingKeys: String, CodingKey { case endpointID = "endpoint_id" }
}

private struct AccessModeSelection: Encodable {
    let accessMode: String
    enum CodingKeys: String, CodingKey { case accessMode = "access_mode" }
}

struct NewConversation: Encodable {
    let title: String
}

private struct RenameConversation: Encodable {
    let title: String
}

struct SecretStatus: Decodable {
    let configured: Bool
}

struct ChatGPTAccountStatus: Decodable {
    let connected: Bool
    let email: String?
    let planEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case connected, email
        case planEnabled = "plan_enabled"
    }
}

struct ChatGPTModel: Decodable, Identifiable, Hashable {
    let slug: String
    let displayName: String
    var id: String { slug }

    enum CodingKeys: String, CodingKey {
        case slug
        case displayName = "display_name"
    }
}

private struct ChatGPTStart: Decodable {
    let authorizationURL: URL
    enum CodingKeys: String, CodingKey { case authorizationURL = "authorization_url" }
}

struct ChatGPTDisconnect: Decodable {
    let remoteRevoked: Bool
    enum CodingKeys: String, CodingKey { case remoteRevoked = "remote_revoked" }
}

private struct OpenAIKeyRequest: Encodable {
    let key: String
}

struct ChatMessage: Decodable, Identifiable, Hashable {
    let id: UUID
    let conversationID: UUID
    let role: String
    let content: String
    let status: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, role, content, status
        case conversationID = "conversation_id"
        case createdAt = "created_at"
    }
}

struct Capabilities: Decodable {
    let provider: String
    let model: String
}

struct MessageRequest: Encodable {
    let content: String
}

enum ChatEvent: Sendable {
    case title(String)
    case delta(String)
    case completed
    case failed(String)
}

private struct EventPayload: Decodable {
    let title: String?
    let text: String?
    let message: String?
}

struct OrbitClient {
    let baseURL: URL

    init(baseURL: URL = URL(string: "http://127.0.0.1:8766")!) {
        self.baseURL = baseURL
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Data non valida: \(value)"
            )
        }
        return decoder
    }

    func listConversations() async throws -> [Conversation] {
        let url = baseURL.appending(path: "v1/conversations")
        let (data, response) = try await URLSession.shared.data(for: try authorizedRequest(url: url))
        try validate(response)
        return try decoder.decode([Conversation].self, from: data)
    }

    func createConversation(title: String = "Nuova chat") async throws -> Conversation {
        let url = baseURL.appending(path: "v1/conversations")
        var request = try authorizedRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(NewConversation(title: title))
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return try decoder.decode(Conversation.self, from: data)
    }

    func deleteConversation(_ conversationID: UUID) async throws {
        let url = baseURL.appending(path: "v1/conversations/\(conversationID)")
        var request = try authorizedRequest(url: url)
        request.httpMethod = "DELETE"
        let (_, response) = try await URLSession.shared.data(for: request)
        try validate(response)
    }

    func renameConversation(_ conversationID: UUID, to title: String) async throws -> Conversation {
        let url = baseURL.appending(path: "v1/conversations/\(conversationID)")
        var request = try authorizedRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RenameConversation(title: title))
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return try decoder.decode(Conversation.self, from: data)
    }

    func capabilities() async throws -> Capabilities {
        let url = baseURL.appending(path: "v1/capabilities")
        let (data, response) = try await URLSession.shared.data(for: try authorizedRequest(url: url))
        try validate(response)
        return try JSONDecoder().decode(Capabilities.self, from: data)
    }

    func listEndpoints() async throws -> [ModelEndpoint] {
        let url = baseURL.appending(path: "v1/endpoints")
        let (data, response) = try await URLSession.shared.data(for: try authorizedRequest(url: url))
        try validate(response)
        return try JSONDecoder().decode([ModelEndpoint].self, from: data)
    }

    func agentSettings() async throws -> AgentSettings {
        let url = baseURL.appending(path: "v1/agent")
        let (data, response) = try await URLSession.shared.data(for: try authorizedRequest(url: url))
        try validate(response)
        return try JSONDecoder().decode(AgentSettings.self, from: data)
    }

    func saveAgentSettings(_ settings: AgentSettings) async throws -> AgentSettings {
        let url = baseURL.appending(path: "v1/agent")
        var request = try authorizedRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(settings)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return try JSONDecoder().decode(AgentSettings.self, from: data)
    }

    func createEndpoint(_ endpoint: NewEndpoint) async throws -> ModelEndpoint {
        let url = baseURL.appending(path: "v1/endpoints")
        var request = try authorizedRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(endpoint)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return try JSONDecoder().decode(ModelEndpoint.self, from: data)
    }

    func selectEndpoint(_ endpointID: UUID, for conversationID: UUID) async throws -> Conversation {
        let url = baseURL.appending(path: "v1/conversations/\(conversationID)/endpoint")
        var request = try authorizedRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(EndpointSelection(endpointID: endpointID))
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return try decoder.decode(Conversation.self, from: data)
    }

    func selectAccessMode(_ accessMode: String, for conversationID: UUID) async throws -> Conversation {
        let url = baseURL.appending(path: "v1/conversations/\(conversationID)/access-mode")
        var request = try authorizedRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(AccessModeSelection(accessMode: accessMode))
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return try decoder.decode(Conversation.self, from: data)
    }

    func listMessages(in conversationID: UUID) async throws -> [ChatMessage] {
        let url = baseURL.appending(path: "v1/conversations/\(conversationID)/messages")
        let (data, response) = try await URLSession.shared.data(for: try authorizedRequest(url: url))
        try validate(response)
        return try decoder.decode([ChatMessage].self, from: data)
    }

    func openAIKeyStatus() async throws -> SecretStatus {
        try await keyStatus(for: "openai")
    }

    func keyStatus(for provider: String) async throws -> SecretStatus {
        let url = baseURL.appending(path: "v1/secrets/\(provider)")
        let (data, response) = try await URLSession.shared.data(for: try authorizedRequest(url: url))
        try validate(response)
        return try JSONDecoder().decode(SecretStatus.self, from: data)
    }

    func chatGPTStatus() async throws -> ChatGPTAccountStatus {
        let url = baseURL.appending(path: "v1/chatgpt/status")
        let (data, response) = try await URLSession.shared.data(for: try authorizedRequest(url: url))
        try validate(response)
        return try JSONDecoder().decode(ChatGPTAccountStatus.self, from: data)
    }

    func startChatGPTSignIn() async throws -> URL {
        let url = baseURL.appending(path: "v1/chatgpt/start")
        var request = try authorizedRequest(url: url)
        request.httpMethod = "POST"
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return try JSONDecoder().decode(ChatGPTStart.self, from: data).authorizationURL
    }

    func chatGPTModels() async throws -> [ChatGPTModel] {
        let url = baseURL.appending(path: "v1/chatgpt/models")
        let (data, response) = try await URLSession.shared.data(for: try authorizedRequest(url: url))
        try validate(response)
        return try JSONDecoder().decode([ChatGPTModel].self, from: data)
    }

    func disconnectChatGPT() async throws -> ChatGPTDisconnect {
        let url = baseURL.appending(path: "v1/chatgpt/account")
        var request = try authorizedRequest(url: url)
        request.httpMethod = "DELETE"
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return try JSONDecoder().decode(ChatGPTDisconnect.self, from: data)
    }

    func saveOpenAIKey(_ key: String) async throws -> SecretStatus {
        try await saveKey(key, for: "openai")
    }

    func saveKey(_ key: String, for provider: String) async throws -> SecretStatus {
        let url = baseURL.appending(path: "v1/secrets/\(provider)")
        var request = try authorizedRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(OpenAIKeyRequest(key: key))
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return try JSONDecoder().decode(SecretStatus.self, from: data)
    }

    func deleteOpenAIKey() async throws -> SecretStatus {
        try await deleteKey(for: "openai")
    }

    func deleteKey(for provider: String) async throws -> SecretStatus {
        let url = baseURL.appending(path: "v1/secrets/\(provider)")
        var request = try authorizedRequest(url: url)
        request.httpMethod = "DELETE"
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return try JSONDecoder().decode(SecretStatus.self, from: data)
    }

    func sendMessage(_ content: String, in conversationID: UUID) -> AsyncThrowingStream<ChatEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let url = baseURL.appending(path: "v1/conversations/\(conversationID)/messages/stream")
                    var request = try authorizedRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(MessageRequest(content: content))
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    try validate(response)
                    var eventName = ""
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        if line.hasPrefix("event: ") {
                            eventName = String(line.dropFirst(7))
                        } else if line.hasPrefix("data: ") {
                            let data = Data(line.dropFirst(6).utf8)
                            let payload = try JSONDecoder().decode(EventPayload.self, from: data)
                            switch eventName {
                            case "user.saved":
                                if let title = payload.title { continuation.yield(.title(title)) }
                            case "text.delta": continuation.yield(.delta(payload.text ?? ""))
                            case "response.completed": continuation.yield(.completed)
                            case "response.failed": continuation.yield(.failed(payload.message ?? "Risposta non disponibile"))
                            default: break
                            }
                            eventName = ""
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw OrbitError.serverUnavailable
        }
    }

    private func authorizedRequest(url: URL) throws -> URLRequest {
        let tokenURL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Orbit Open/core-token")
        guard let token = try? String(contentsOf: tokenURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
            throw OrbitError.tokenUnavailable
        }
        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "X-Orbit-Token")
        return request
    }
}

enum OrbitError: LocalizedError {
    case serverUnavailable
    case tokenUnavailable

    var errorDescription: String? {
        switch self {
        case .serverUnavailable:
            "Orbit Core non è disponibile. Avvia il servizio locale e riprova."
        case .tokenUnavailable:
            "Token locale Orbit assente. Avvia Orbit Core e riprova."
        }
    }
}
