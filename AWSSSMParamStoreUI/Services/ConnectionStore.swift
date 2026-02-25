import Foundation
import SwiftUI
import Combine
import LocalAuthentication

/// Manages persistence of connections using UserDefaults and Keychain.
/// Secrets are cached in memory after the first read so keychain is accessed
/// at most once per session per connection.
@MainActor
class ConnectionStore: ObservableObject {
    static let shared = ConnectionStore()

    private let connectionsKey = "savedConnections"
    private let lastConnectionIdKey = "lastConnectionId"

    @Published private(set) var connections: [Connection] = []
    @Published var lastConnectionId: UUID?

    // In-memory cache: populated on add/update, cleared on delete.
    // Avoids repeated keychain reads (and Touch ID prompts) within a session.
    private var secretCache: [UUID: String] = [:]
    private var tokenCache:  [UUID: String] = [:]

    private init() {
        loadConnections()
        loadLastConnectionId()
    }

    // MARK: - Connection CRUD

    func addConnection(_ connection: Connection, secretKey: String? = nil, sessionToken: String? = nil) {
        if connection.type == .credentials {
            if let secretKey {
                try? KeychainService.saveSecretKey(secretKey, for: connection.id)
                secretCache[connection.id] = secretKey
            }
            if let sessionToken, !sessionToken.isEmpty {
                try? KeychainService.saveSessionToken(sessionToken, for: connection.id)
                tokenCache[connection.id] = sessionToken
            }
        }
        connections.append(connection)
        saveConnections()
    }

    func updateConnection(_ connection: Connection, secretKey: String? = nil, sessionToken: String? = nil) {
        guard let index = connections.firstIndex(where: { $0.id == connection.id }) else { return }

        if connection.type == .credentials {
            if let secretKey {
                try? KeychainService.saveSecretKey(secretKey, for: connection.id)
                secretCache[connection.id] = secretKey
            }
            if let sessionToken {
                if sessionToken.isEmpty {
                    try? KeychainService.deleteSessionToken(for: connection.id)
                    tokenCache.removeValue(forKey: connection.id)
                } else {
                    try? KeychainService.saveSessionToken(sessionToken, for: connection.id)
                    tokenCache[connection.id] = sessionToken
                }
            }
        }

        connections[index] = connection
        saveConnections()
    }

    func deleteConnection(_ connection: Connection) {
        try? KeychainService.deleteSecretKey(for: connection.id)
        try? KeychainService.deleteSessionToken(for: connection.id)
        secretCache.removeValue(forKey: connection.id)
        tokenCache.removeValue(forKey: connection.id)

        connections.removeAll { $0.id == connection.id }
        saveConnections()

        if lastConnectionId == connection.id {
            lastConnectionId = nil
            saveLastConnectionId()
        }
    }

    func connection(for id: UUID) -> Connection? {
        connections.first { $0.id == id }
    }

    // MARK: - Secret Access (sync, cache-first)
    // Used by ConnectionPickerSheet for pre-filling edit fields.
    // Returns from cache immediately if available; falls back to a keychain
    // read (which may show a Touch ID / passcode prompt the first time).

    func secretKey(for connection: Connection) -> String? {
        guard connection.type == .credentials else { return nil }
        if let cached = secretCache[connection.id] { return cached }
        let value = KeychainService.getSecretKey(for: connection.id)
        if let value { secretCache[connection.id] = value }
        return value
    }

    func sessionToken(for connection: Connection) -> String? {
        guard connection.type == .credentials else { return nil }
        if let cached = tokenCache[connection.id] { return cached }
        let value = KeychainService.getSessionToken(for: connection.id)
        if let value { tokenCache[connection.id] = value }
        return value
    }

    // MARK: - Secret Access (async, Touch ID)
    // Used by AppState.connect. Authenticates exactly once with a single LAContext,
    // then reads both the secret key and session token with the same context.

    func fetchCredentialsForConnect(_ connection: Connection) async -> (secretKey: String?, sessionToken: String?) {
        guard connection.type == .credentials else { return (nil, nil) }

        let secretCached = secretCache[connection.id]
        let tokenCached  = tokenCache[connection.id]

        // Both already in cache — no keychain access needed at all
        if let secret = secretCached {
            return (secret, tokenCached)
        }

        // Authenticate once for both reads
        let context = LAContext()
        let authenticated = await withCheckedContinuation { continuation in
            context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Access AWS credentials for \"\(connection.name)\""
            ) { success, _ in
                continuation.resume(returning: success)
            }
        }
        guard authenticated else { return (nil, nil) }

        let secret = KeychainService.getSecretKey(for: connection.id, context: context)
        if let secret { secretCache[connection.id] = secret }

        let token = tokenCached ?? KeychainService.getSessionToken(for: connection.id, context: context)
        if let token { tokenCache[connection.id] = token }

        return (secret, token)
    }

    // MARK: - Last Connection

    func setLastConnection(_ connection: Connection?) {
        lastConnectionId = connection?.id
        saveLastConnectionId()
    }

    var lastConnection: Connection? {
        guard let id = lastConnectionId else { return nil }
        return connection(for: id)
    }

    // MARK: - Persistence

    private func loadConnections() {
        guard let data = UserDefaults.standard.data(forKey: connectionsKey) else { return }
        do {
            connections = try JSONDecoder().decode([Connection].self, from: data)
        } catch {
            print("Failed to decode connections: \(error)")
            connections = []
        }
    }

    private func saveConnections() {
        do {
            let data = try JSONEncoder().encode(connections)
            UserDefaults.standard.set(data, forKey: connectionsKey)
        } catch {
            print("Failed to encode connections: \(error)")
        }
    }

    private func loadLastConnectionId() {
        guard let idString = UserDefaults.standard.string(forKey: lastConnectionIdKey),
              let id = UUID(uuidString: idString) else { return }
        lastConnectionId = id
    }

    private func saveLastConnectionId() {
        if let id = lastConnectionId {
            UserDefaults.standard.set(id.uuidString, forKey: lastConnectionIdKey)
        } else {
            UserDefaults.standard.removeObject(forKey: lastConnectionIdKey)
        }
    }

    // MARK: - Helpers

    var hasConnections: Bool { !connections.isEmpty }

    func uniqueName(base: String) -> String {
        var name = base
        var counter = 1
        while connections.contains(where: { $0.name == name }) {
            counter += 1
            name = "\(base) \(counter)"
        }
        return name
    }
}
