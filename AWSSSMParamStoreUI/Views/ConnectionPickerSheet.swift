import SwiftUI

struct ConnectionPickerSheet: View {
    @ObservedObject var connectionStore: ConnectionStore
    let currentConnectionId: UUID?
    let onConnect: (Connection) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedId: UUID?
    @State private var editingConnection: Connection?
    @State private var editingSecretKey: String = ""
    @State private var editingSessionToken: String = ""
    @State private var isTestingConnection = false
    @State private var testResult: TestResult?

    private let profiles = ProfileManager.listProfiles()

    private enum TestResult {
        case success
        case failure(String)
    }

    var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            detailContent
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Connect") {
                    if hasChanges { saveConnection() }
                    guard let id = selectedId,
                          let connection = connectionStore.connection(for: id) else { return }
                    onConnect(connection)
                    dismiss()
                }
                .disabled(selectedId == nil)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        addNewConnection()
                    } label: {
                        Label("New Connection", systemImage: "plus")
                    }
                    Divider()
                    Button {
                        quickConnectToLocalStack()
                    } label: {
                        Label("Quick Connect to LocalStack", systemImage: "laptopcomputer")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .frame(minWidth: 640, minHeight: 460)
        .onChange(of: editingConnection) { _, _ in testResult = nil }
        .onChange(of: editingSecretKey) { _, _ in testResult = nil }
        .onChange(of: editingSessionToken) { _, _ in testResult = nil }
        .onAppear {
            let preselect = currentConnectionId
                ?? connectionStore.lastConnectionId
                ?? connectionStore.connections.first?.id
            selectedId = preselect
            if let id = preselect, let conn = connectionStore.connection(for: id) {
                editingConnection = conn
                loadSecretKey(for: conn)
            }
        }
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            Group {
                if connectionStore.connections.isEmpty {
                    ContentUnavailableView(
                        "No Connections",
                        systemImage: "cable.connector",
                        description: Text("Use the + button to add a connection.")
                    )
                } else {
                    connectionList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack(spacing: 0) {
                Button {
                    addNewConnection()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .help("Add Connection")

                Button {
                    deleteSelectedConnection()
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .disabled(selectedId == nil)
                .help("Remove Connection")

                Spacer()
            }
            .padding(6)
            .background(.bar)
        }
    }

    private var connectionList: some View {
        List(selection: $selectedId) {
            connectionSection(
                title: "LocalStack",
                connections: connectionStore.connections.filter { $0.type == .localstack }
            )
            connectionSection(
                title: "SSO Profile",
                connections: connectionStore.connections.filter { $0.type == .ssoProfile }
            )
            connectionSection(
                title: "Credentials",
                connections: connectionStore.connections.filter { $0.type == .credentials }
            )
        }
        .listStyle(.sidebar)
        .onChange(of: selectedId) { _, newId in
            guard let id = newId, let conn = connectionStore.connection(for: id) else { return }
            editingConnection = conn
            loadSecretKey(for: conn)
            testResult = nil
        }
    }

    @ViewBuilder
    private func connectionSection(title: String, connections: [Connection]) -> some View {
        if !connections.isEmpty {
            Section(title) {
                ForEach(connections) { connection in
                    connectionRow(connection)
                        .tag(connection.id)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteConnection(connection)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
    }

    private func connectionRow(_ connection: Connection) -> some View {
        HStack(spacing: 10) {
            Image(systemName: connection.type.icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(connection.name)
                    .lineLimit(1)

                Text(connection.region)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if connection.id == currentConnectionId {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                    .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailContent: some View {
        if let connection = editingConnection {
            connectionForm(connection)
        } else {
            ContentUnavailableView(
                "No Connection Selected",
                systemImage: "sidebar.left",
                description: Text("Select a connection from the sidebar.")
            )
        }
    }

    private func connectionForm(_ connection: Connection) -> some View {
        Form {
            Section {
                LabeledContent("Name") {
                    TextField("", text: binding(for: \.name), prompt: Text("My Connection"))
                }
                LabeledContent("Type") {
                    Picker("", selection: binding(for: \.type)) {
                        ForEach(ConnectionType.allCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.icon).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                LabeledContent("Region") {
                    Picker("", selection: binding(for: \.region)) {
                        ForEach(RegionHelper.shared.groupedRegions) { group in
                            Section(group.name) {
                                ForEach(group.regions, id: \.self) { region in
                                    Text(RegionHelper.shared.regionName(region)).tag(region)
                                }
                            }
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 240)
                }
            }

            Section {
                switch connection.type {
                case .localstack:
                    LabeledContent("Endpoint") {
                        TextField("", text: binding(for: \.endpoint, default: ""), prompt: Text("http://localhost:4566"))
                    }
                case .ssoProfile:
                    LabeledContent("Profile") {
                        Picker("", selection: binding(for: \.profileName, default: "")) {
                            Text("Select a profile...").tag("")
                            ForEach(profiles, id: \.self) { profile in
                                Text(profile).tag(profile)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 200)
                    }
                case .credentials:
                    LabeledContent("Access Key ID") {
                        TextField("", text: binding(for: \.accessKeyId, default: ""), prompt: Text("AKIA..."))
                            .font(.system(.body, design: .monospaced))
                    }
                    LabeledContent("Secret Access Key") {
                        SecureField("", text: $editingSecretKey, prompt: Text("Secret key"))
                            .font(.system(.body, design: .monospaced))
                    }
                    LabeledContent("Session Token") {
                        SecureField("", text: $editingSessionToken, prompt: Text("Optional — for temporary credentials"))
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Button {
                            testConnection()
                        } label: {
                            if isTestingConnection {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("Testing...")
                                }
                            } else {
                                Text("Test Connection")
                            }
                        }
                        .disabled(isTestingConnection || !isConnectionValid)

                        Spacer()

                        Button("Save") {
                            saveConnection()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!isConnectionValid || !hasChanges)
                    }

                    if let result = testResult {
                        Group {
                            switch result {
                            case .success:
                                Label("Connected", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            case .failure(let msg):
                                HStack(alignment: .top, spacing: 6) {
                                    Label(msg, systemImage: "xmark.circle.fill")
                                        .foregroundStyle(.red)
                                    Spacer()
                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(msg, forType: .string)
                                    } label: {
                                        Image(systemName: "doc.on.doc")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Copy error message")
                                }
                            }
                        }
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Actions

    private func addNewConnection() {
        let newConnection = Connection(
            name: connectionStore.uniqueName(base: "New Connection"),
            type: .localstack,
            region: "eu-west-1"
        )
        connectionStore.addConnection(newConnection)
        selectedId = newConnection.id
        editingConnection = newConnection
        editingSecretKey = ""
        editingSessionToken = ""
        testResult = nil
    }

    private func quickConnectToLocalStack() {
        let localstack = Connection.defaultLocalStack()
        connectionStore.addConnection(localstack)
        selectedId = localstack.id
        editingConnection = localstack
        editingSecretKey = ""
        editingSessionToken = ""
        testResult = nil
    }

    private func deleteSelectedConnection() {
        guard let id = selectedId,
              let connection = connectionStore.connection(for: id) else { return }
        deleteConnection(connection)
    }

    private func deleteConnection(_ connection: Connection) {
        connectionStore.deleteConnection(connection)
        if selectedId == connection.id {
            selectedId = connectionStore.connections.first?.id
            if let newId = selectedId, let conn = connectionStore.connection(for: newId) {
                editingConnection = conn
                loadSecretKey(for: conn)
            } else {
                editingConnection = nil
            }
            testResult = nil
        }
    }

    private func saveConnection() {
        guard var connection = editingConnection else { return }
        if connection.endpoint?.isEmpty == true {
            connection.endpoint = nil
        }
        let secretKey = connection.type == .credentials ? editingSecretKey : nil
        let sessionToken = connection.type == .credentials ? editingSessionToken : nil
        if connectionStore.connection(for: connection.id) != nil {
            connectionStore.updateConnection(connection, secretKey: secretKey, sessionToken: sessionToken)
        } else {
            connectionStore.addConnection(connection, secretKey: secretKey, sessionToken: sessionToken)
        }
        editingConnection = connection
        testResult = nil
    }

    private func testConnection() {
        guard let connection = editingConnection else { return }
        isTestingConnection = true
        testResult = nil

        Task {
            let service = SSMService()
            do {
                let secretKey = connection.type == .credentials ? editingSecretKey : nil
                let sessionToken = connection.type == .credentials ? editingSessionToken : nil
                try await service.configure(with: connection, secretKey: secretKey, sessionToken: sessionToken)
                try await service.testConnection()
                await MainActor.run {
                    testResult = .success
                    isTestingConnection = false
                }
            } catch {
                await MainActor.run {
                    let message: String
                    switch connection.type {
                    case .ssoProfile:
                        message = "Try: aws sso login --profile \(connection.profileName ?? "default")"
                    case .credentials:
                        if case ServiceError.awsError(let detail) = error {
                            message = detail
                        } else {
                            message = "Check your access key ID, secret access key, and selected region.\n\n\(error.localizedDescription)"
                        }
                    case .localstack:
                        message = "Could not reach LocalStack. Is it running at \(connection.effectiveEndpoint)?"
                    }
                    testResult = .failure(message)
                    isTestingConnection = false
                }
            }
        }
    }

    private func loadSecretKey(for connection: Connection) {
        editingSecretKey = connection.type == .credentials
            ? (connectionStore.secretKey(for: connection) ?? "")
            : ""
        editingSessionToken = connection.type == .credentials
            ? (connectionStore.sessionToken(for: connection) ?? "")
            : ""
    }

    // MARK: - Validation & Bindings

    private var isConnectionValid: Bool {
        guard let connection = editingConnection else { return false }
        guard !connection.name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        switch connection.type {
        case .localstack: return true
        case .ssoProfile: return !(connection.profileName ?? "").isEmpty
        case .credentials: return !(connection.accessKeyId ?? "").isEmpty && !editingSecretKey.isEmpty
        }
    }

    private var hasChanges: Bool {
        guard let editing = editingConnection else { return false }
        guard let original = connectionStore.connection(for: editing.id) else {
            return true // New unsaved connection
        }
        if editing != original { return true }
        if editing.type == .credentials {
            if editingSecretKey != (connectionStore.secretKey(for: original) ?? "") { return true }
            if editingSessionToken != (connectionStore.sessionToken(for: original) ?? "") { return true }
        }
        return false
    }

    private func binding<T>(for keyPath: WritableKeyPath<Connection, T>) -> Binding<T> {
        Binding(
            get: { editingConnection![keyPath: keyPath] },
            set: { editingConnection?[keyPath: keyPath] = $0 }
        )
    }

    private func binding<T>(for keyPath: WritableKeyPath<Connection, T?>, default defaultValue: T) -> Binding<T> {
        Binding(
            get: { editingConnection?[keyPath: keyPath] ?? defaultValue },
            set: { editingConnection?[keyPath: keyPath] = $0 }
        )
    }
}

// MARK: - Toolbar Connection Button

struct ConnectionButton: View {
    let connection: Connection?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let connection {
                    Image(systemName: connection.type.icon)
                    Text(connection.name)
                } else {
                    Image(systemName: "externaldrive.badge.questionmark")
                    Text("No Connection")
                }
            }
        }
        .help("Change Connection")
    }
}
