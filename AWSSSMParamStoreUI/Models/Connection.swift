import Foundation

/// The type of connection to AWS Parameter Store
enum ConnectionType: String, Codable, CaseIterable {
    case localstack = "LocalStack"
    case ssoProfile = "SSO Profile"
    case credentials = "Credentials"
    
    var icon: String {
        switch self {
        case .localstack: return "laptopcomputer"
        case .ssoProfile: return "person.circle.fill"
        case .credentials: return "key.fill"
        }
    }
    
    var description: String {
        switch self {
        case .localstack: return "Connect to a local LocalStack instance"
        case .ssoProfile: return "Use an AWS SSO profile from ~/.aws/config"
        case .credentials: return "Use AWS access key and secret key"
        }
    }
}

/// A saved connection configuration
struct Connection: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var type: ConnectionType
    var region: String
    
    // LocalStack specific
    var endpoint: String?
    
    // SSO Profile specific
    var profileName: String?
    
    // Note: For credentials type, access key ID is stored here,
    // but secret access key is stored securely in Keychain
    var accessKeyId: String?
    
    init(
        id: UUID = UUID(),
        name: String,
        type: ConnectionType,
        region: String = "eu-west-1",
        endpoint: String? = nil,
        profileName: String? = nil,
        accessKeyId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.region = region
        self.endpoint = endpoint
        self.profileName = profileName
        self.accessKeyId = accessKeyId
    }
    
    /// Default LocalStack endpoint
    static let defaultLocalStackEndpoint = "http://localhost:4566"
    
    /// The effective endpoint for LocalStack connections
    var effectiveEndpoint: String {
        endpoint ?? Self.defaultLocalStackEndpoint
    }
    
    /// Create a default LocalStack connection
    static func defaultLocalStack() -> Connection {
        Connection(
            name: "LocalStack",
            type: .localstack,
            region: "eu-west-1"
        )
    }
    
    /// Display subtitle showing connection details
    var subtitle: String {
        switch type {
        case .localstack:
            return effectiveEndpoint
        case .ssoProfile:
            return profileName ?? "No profile"
        case .credentials:
            if let keyId = accessKeyId {
                // Show masked access key
                let prefix = String(keyId.prefix(4))
                let suffix = String(keyId.suffix(4))
                return "\(prefix)...\(suffix)"
            }
            return "No credentials"
        }
    }
}

