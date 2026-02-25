import Foundation
import AWSSSM
import AWSClientRuntime
import ClientRuntime
import AWSSDKIdentity
import SmithyIdentity
import enum Smithy.URIScheme
@preconcurrency internal import SmithyHTTPClientAPI

enum ServiceError: Error {
    case notConfigured
    case awsError(String)
}

actor SSMService {
    private var client: SSMClient?
    private(set) var currentConnection: Connection?
    
    private static let localStackEndpoint = "http://localhost:4566"

    /// Configure the service with a Connection object
    func configure(with connection: Connection, secretKey: String? = nil, sessionToken: String? = nil) async throws {
        self.currentConnection = connection

        switch connection.type {
        case .localstack:
            try await configureLocalStack(region: connection.region, endpoint: connection.effectiveEndpoint)
        case .ssoProfile:
            try await configureSSO(profileName: connection.profileName, region: connection.region)
        case .credentials:
            guard let accessKeyId = connection.accessKeyId, let secretKey = secretKey else {
                throw ServiceError.notConfigured
            }
            try await configureCredentials(accessKeyId: accessKeyId, secretAccessKey: secretKey, sessionToken: sessionToken, region: connection.region)
        }
    }
    
    /// Configure for LocalStack
    private func configureLocalStack(region: String, endpoint: String) async throws {
        // LocalStack doesn't validate credentials, but we need to provide some
        let staticCredentials = AWSCredentialIdentity(
            accessKey: "test",
            secret: "test"
        )
        
        // Force HTTP protocol for LocalStack
        let httpConfig = HttpClientConfiguration(
            connectTimeout: 30,
            socketTimeout: 30,
            protocolType: URIScheme.http
        )
        
        let config = try await SSMClient.SSMClientConfiguration(
            region: region,
            httpClientConfiguration: httpConfig
        )
        config.endpoint = endpoint
        config.awsCredentialIdentityResolver = StaticAWSCredentialIdentityResolver(staticCredentials)
        
        self.client = SSMClient(config: config)
    }
    
    /// Configure for AWS SSO Profile
    private func configureSSO(profileName: String?, region: String) async throws {
        let config = try await SSMClient.SSMClientConfiguration(region: region)

        if let profileName = profileName, !profileName.isEmpty {
            // Explicitly use the specified profile
            // Note: If SharedCredentialsProvider is not found, verify import of AWSClientRuntime or AWSSDKIdentity
            // Attempting to use the IdentityResolver directly if Provider is not the name
            config.awsCredentialIdentityResolver = ProfileAWSCredentialIdentityResolver(profileName: profileName)
        }
        
        self.client = SSMClient(config: config)
    }
    
    /// Configure for explicit AWS Credentials
    private func configureCredentials(accessKeyId: String, secretAccessKey: String, sessionToken: String? = nil, region: String) async throws {
        let staticCredentials = AWSCredentialIdentity(
            accessKey: accessKeyId,
            secret: secretAccessKey,
            accountID: nil,
            expiration: nil,
            sessionToken: sessionToken
        )

        let config = try await SSMClient.SSMClientConfiguration(region: region)
        config.awsCredentialIdentityResolver = StaticAWSCredentialIdentityResolver(staticCredentials)

        self.client = SSMClient(config: config)
    }

    // MARK: - Legacy configure method (for backward compatibility during migration)
    
    func configure(profileName: String?, region: String = "us-east-1", useLocalStack: Bool = false) async throws {
        if useLocalStack {
            let connection = await MainActor.run { Connection(name: "LocalStack", type: .localstack, region: region) }
            try await configure(with: connection)
        } else if let profileName = profileName {
            let connection = await MainActor.run { Connection(name: profileName, type: .ssoProfile, region: region, profileName: profileName) }
            try await configure(with: connection)
        } else {
            let connection = await MainActor.run { Connection(name: "Default", type: .ssoProfile, region: region) }
            try await configure(with: connection)
        }
    }

    /// Phase 1: returns a stream of metadata pages (50/page, no values).
    /// Accesses actor-isolated `client` here, then the stream's Task uses the captured reference.
    func describeAllParameters(path: String = "/") async throws -> AsyncThrowingStream<[SSMClientTypes.ParameterMetadata], Error> {
        guard let client = client else { throw ServiceError.notConfigured }
        return AsyncThrowingStream { continuation in
            Task {
                var nextToken: String? = nil
                repeat {
                    let filter = SSMClientTypes.ParameterStringFilter(
                        key: "Path",
                        option: "Recursive",
                        values: [path]
                    )
                    let input = DescribeParametersInput(
                        maxResults: 50,
                        nextToken: nextToken,
                        parameterFilters: [filter]
                    )
                    do {
                        let output = try await client.describeParameters(input: input)
                        continuation.yield(output.parameters ?? [])
                        nextToken = output.nextToken
                    } catch {
                        continuation.finish(throwing: error)
                        return
                    }
                } while nextToken != nil
                continuation.finish()
            }
        }
    }

    /// Phase 2: fetch actual values for up to 10 named parameters.
    func fetchParameterValues(names: [String]) async throws -> [SSMClientTypes.Parameter] {
        guard let client = client else { throw ServiceError.notConfigured }
        let input = GetParametersInput(names: names, withDecryption: true)
        let output = try await client.getParameters(input: input)
        return output.parameters ?? []
    }

    func fetchAllParameters(path: String = "/") async throws -> [SSMClientTypes.Parameter] {
        guard let client = client else { throw ServiceError.notConfigured }
        
        var parameters: [SSMClientTypes.Parameter] = []
        var nextToken: String? = nil
        
        repeat {
            let input = GetParametersByPathInput(
                nextToken: nextToken,
                path: path,
                recursive: true,
                withDecryption: true
            )
            
            let output = try await client.getParametersByPath(input: input)
            if let params = output.parameters {
                print("Fetched \(params.count) parameters")
                parameters.append(contentsOf: params)
            }
            nextToken = output.nextToken
        } while nextToken != nil
        
        print("Total parameters fetched: \(parameters.count)")
        return parameters
    }

    func updateParameter(name: String, value: String) async throws -> Date {
        guard let client = client else { throw ServiceError.notConfigured }
        
        let input = PutParameterInput(
            name: name,
            overwrite: true,
            value: value
        )
        
        _ = try await client.putParameter(input: input)
        return Date() // Return current time as approx update time
    }
    
    func createParameter(name: String, value: String, isSecure: Bool = false) async throws -> Date {
        guard let client = client else { throw ServiceError.notConfigured }
        
        let input = PutParameterInput(
            name: name,
            type: isSecure ? .secureString : .string,
            value: value
        )
        
        _ = try await client.putParameter(input: input)
        return Date()
    }
    
    func deleteParameter(name: String) async throws {
        guard let client = client else { throw ServiceError.notConfigured }
        
        let input = DeleteParameterInput(name: name)
        _ = try await client.deleteParameter(input: input)
    }
    
    /// Test the current connection by attempting to list parameters
    func testConnection() async throws {
        guard let client = client else { throw ServiceError.notConfigured }

        let input = GetParametersByPathInput(
            maxResults: 1,
            path: "/",
            recursive: false
        )

        do {
            _ = try await client.getParametersByPath(input: input)
        } catch let error as any AWSServiceError {
            let code = error.typeName ?? error.errorCode ?? "unknown"
            let detail = error.message.map { ": \($0)" } ?? ""
            switch code {
            case "InvalidClientTokenId", "InvalidAccessKeyId":
                throw ServiceError.awsError("Invalid access key ID\(detail)")
            case "AuthFailure", "InvalidSignatureException", "SignatureDoesNotMatch":
                throw ServiceError.awsError("Authentication failed. Check your secret access key and that your system clock is synced.\(detail)")
            case "AccessDeniedException":
                throw ServiceError.awsError("Access denied. Your credentials don't have permission to access SSM Parameter Store.\(detail)")
            case "ExpiredTokenException":
                throw ServiceError.awsError("Credentials have expired. Refresh your access keys.\(detail)")
            default:
                throw ServiceError.awsError("AWS error (\(code))\(detail)")
            }
        }
    }
}
