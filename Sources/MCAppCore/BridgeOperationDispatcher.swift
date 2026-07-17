import Foundation
import MCContainerBridge
import MCModel
import MCSystemLifecycle

public enum BridgeOperationDispatcherError: Error, Equatable, Sendable {
    case invalidField(String)
    case unsupportedOperation(String)
    case explicitConsentRequired(String)
}

public struct BridgeOperationDispatcher: OperationDispatching, Sendable {
    public static let supportedOperationIDs: Set<String> = [
        "core.run", "core.build",
        "containers.create", "containers.start", "containers.stop", "containers.kill",
        "containers.delete", "containers.list", "containers.exec", "containers.export",
        "containers.logs", "containers.inspect", "containers.stats", "containers.copy",
        "containers.prune",
        "images.list", "images.pull", "images.push", "images.save", "images.load",
        "images.tag", "images.delete", "images.prune", "images.inspect",
        "builder.start", "builder.status", "builder.stop", "builder.delete",
        "networks.create", "networks.delete", "networks.prune", "networks.list",
        "networks.inspect",
        "volumes.create", "volumes.delete", "volumes.prune", "volumes.list",
        "volumes.inspect",
        "registries.login", "registries.logout", "registries.list",
        "machines.create", "machines.run", "machines.list", "machines.inspect",
        "machines.set", "machines.set-default", "machines.logs", "machines.stop",
        "machines.delete",
        "system.start", "system.stop", "system.status", "system.version", "system.logs",
        "system.disk-usage",
        "dns.create", "dns.delete", "dns.list", "kernel.set", "configuration.manage"
    ]

    private let bridge: any RuntimeBridge

    public init(bridge: (any RuntimeBridge)? = nil) {
        self.bridge = bridge ?? AppleRuntimeBridge(dnsBackend: PrivilegedDNSBackend())
    }

    // The exhaustive operation switch is the UI-to-bridge authority for the reviewed 1.1.0 contract.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    public func dispatch(_ draft: OperationDraft) async throws -> OperationDispatchResult {
        guard Self.supportedOperationIDs.contains(draft.operationID) else {
            throw BridgeOperationDispatcherError.unsupportedOperation(draft.operationID)
        }
        let fields = DraftReader(draft)
        switch draft.operationID {
        case "core.run":
            let request = try containerCreateRequest(fields)
            let result = try await bridge.containers.run(.init(
                create: request,
                attach: !fields.bool("detach"),
                removeAfterExit: fields.bool("removeAfterStop")
            ))
            return .init(summary: "Started \(result.container.name)")
        case "core.build":
            let context = try fields.requiredFileURL("contextDirectory")
            let dockerfile = try fields.fileURL("dockerfile")
            let request = BuildRequest(
                context: context,
                dockerfile: dockerfile,
                tags: fields.strings("tags"),
                platforms: fields.strings("platforms"),
                buildArguments: fields.keyValues("buildArguments"),
                secretReferences: fields.strings("secrets").map {
                    BuildSecretReference(id: $0, environmentVariable: $0)
                },
                outputs: fields.keyValues("outputs"),
                cacheImports: fields.strings("cacheImports"),
                cacheExports: fields.strings("cacheExports")
            )
            let count = try await consume(bridge.builds.build(request))
            return .init(summary: "Build completed with \(count) progress updates")
        case "containers.create":
            let result = try await bridge.containers.create(containerCreateRequest(fields))
            return .init(summary: "Created \(result.name)")
        case "containers.start":
            return try await batch(
                bridge.containers.start(ids: fields.identifiers("containerID", "containerIDs")),
                action: "Started"
            )
        case "containers.stop":
            let timeout = fields.int("timeoutSeconds").map { Duration.seconds($0) }
            return try await batch(
                bridge.containers.stop(
                    ids: fields.identifiers("containerID", "containerIDs"),
                    timeout: timeout
                ),
                action: "Stopped"
            )
        case "containers.kill":
            return try await batch(
                bridge.containers.kill(
                    ids: fields.identifiers("containerID", "containerIDs"),
                    signal: fields.string("signal") ?? "SIGKILL"
                ),
                action: "Signaled"
            )
        case "containers.delete":
            return try await batch(
                bridge.containers.delete(
                    ids: fields.identifiers("containerID", "containerIDs"),
                    force: fields.bool("force")
                ),
                action: "Deleted"
            )
        case "containers.list":
            let values = try await bridge.containers.list()
            return .init(summary: "Found \(values.count) containers")
        case "containers.exec":
            let request = try ProcessRequest(
                resourceID: fields.requiredString("containerID"),
                arguments: fields.strings("arguments"),
                environment: fields.keyValues("environment"),
                workingDirectory: fields.string("workingDirectory"),
                user: fields.string("user"),
                tty: fields.bool("tty"),
                interactive: fields.bool("interactive")
            )
            return try await process(bridge.containers.exec(request), fields: fields)
        case "containers.export":
            let id = try fields.requiredString("containerID")
            try await bridge.containers.export(
                id: id,
                destination: fields.requiredFileURL("output")
            )
            return .init(summary: "Exported \(id)")
        case "containers.logs":
            let id = try fields.requiredString("containerID")
            let count = try await consume(bridge.containers.logs(id: id, options: logOptions(fields)))
            return .init(summary: "Read \(count) log records from \(id)")
        case "containers.inspect":
            let ids = fields.identifiers("containerID", "containerIDs")
            for id in ids {
                _ = try await bridge.containers.inspect(id: id)
            }
            return .init(summary: "Inspected \(ids.count) containers")
        case "containers.stats":
            let ids = fields.identifiers("containerID", "containerIDs")
            var count = 0
            for id in ids {
                count += try await consume(bridge.containers.stats(id: id), limit: 1)
            }
            return .init(summary: "Read \(count) container statistics samples")
        case "containers.copy":
            try await bridge.containers.copy(.init(
                source: copyEndpoint(fields.requiredString("source")),
                destination: copyEndpoint(fields.requiredString("destination"))
            ))
            return .init(summary: "Copy completed")
        case "containers.prune":
            return try await prune(bridge.containers.prune(), kind: "containers")
        case "images.list":
            return try await .init(summary: "Found \(bridge.images.list().count) images")
        case "images.pull":
            let request = imageTransferRequest(fields)
            let count = try await consume(bridge.images.pull(request))
            return .init(summary: "Pulled \(request.reference) with \(count) progress updates")
        case "images.push":
            let request = imageTransferRequest(fields)
            let count = try await consume(bridge.images.push(request))
            return .init(summary: "Pushed \(request.reference) with \(count) progress updates")
        case "images.save":
            let references = fields.strings("references")
            try await bridge.images.save(
                references: references,
                destination: fields.requiredFileURL("output")
            )
            return .init(summary: "Saved \(references.count) images")
        case "images.load":
            let values = try await bridge.images.load(source: fields.requiredFileURL("input"))
            return .init(summary: "Loaded \(values.count) images")
        case "images.tag":
            let source = try fields.requiredString("source")
            let target = try fields.requiredString("target")
            try await bridge.images.tag(source: source, target: target)
            return .init(summary: "Tagged \(source) as \(target)")
        case "images.delete":
            return try await batch(bridge.images.delete(references: fields.strings("images")), action: "Deleted")
        case "images.prune":
            return try await prune(bridge.images.prune(), kind: "images")
        case "images.inspect":
            let references = fields.strings("images")
            for reference in references {
                _ = try await bridge.images.inspect(reference: reference)
            }
            return .init(summary: "Inspected \(references.count) images")
        case "builder.start":
            let result = try await bridge.builders.start(.init(resources: resources(fields)))
            return .init(summary: "Builder is \(result.state.rawValue)")
        case "builder.status":
            let result = try await bridge.builders.status()
            return .init(summary: "Builder is \(result.state.rawValue)")
        case "builder.stop":
            try await bridge.builders.stop()
            return .init(summary: "Builder stopped")
        case "builder.delete":
            try await bridge.builders.delete()
            return .init(summary: "Builder deleted")
        case "networks.create":
            let name = try fields.requiredString("name")
            let subnet = fields.string("ipv4Subnet") ?? fields.string("ipv6Subnet")
            _ = try await bridge.networks.create(.init(
                name: name,
                subnet: subnet,
                labels: Dictionary(uniqueKeysWithValues: fields.keyValues("labels").map { ($0.key, $0.value) })
            ))
            return .init(summary: "Created network \(name)")
        case "networks.delete":
            return try await batch(bridge.networks.delete(ids: fields.strings("networkNames")), action: "Deleted")
        case "networks.prune":
            return try await prune(bridge.networks.prune(), kind: "networks")
        case "networks.list":
            return try await .init(summary: "Found \(bridge.networks.list().count) networks")
        case "networks.inspect":
            let ids = fields.strings("networks")
            for id in ids {
                _ = try await bridge.networks.inspect(id: id)
            }
            return .init(summary: "Inspected \(ids.count) networks")
        case "volumes.create":
            let name = try fields.requiredString("name")
            _ = try await bridge.volumes.create(.init(
                name: name,
                labels: Dictionary(uniqueKeysWithValues: fields.keyValues("labels").map { ($0.key, $0.value) })
            ))
            return .init(summary: "Created volume \(name)")
        case "volumes.delete":
            return try await batch(bridge.volumes.delete(names: fields.strings("names")), action: "Deleted")
        case "volumes.prune":
            return try await prune(bridge.volumes.prune(), kind: "volumes")
        case "volumes.list":
            return try await .init(summary: "Found \(bridge.volumes.list().count) volumes")
        case "volumes.inspect":
            let names = fields.strings("names")
            for name in names {
                _ = try await bridge.volumes.inspect(name: name)
            }
            return .init(summary: "Inspected \(names.count) volumes")
        case "registries.login":
            let server = try fields.requiredString("server")
            _ = try await bridge.registries.login(.init(
                server: server,
                username: fields.requiredString("username"),
                password: Data((fields.string("password") ?? "").utf8)
            ))
            return .init(summary: "Signed in to \(server)")
        case "registries.logout":
            let server = try fields.requiredString("server")
            try await bridge.registries.logout(server: server)
            return .init(summary: "Signed out of \(server)")
        case "registries.list":
            return try await .init(summary: "Found \(bridge.registries.list().count) registries")
        case "machines.create":
            let request = try machineCreateRequest(fields)
            _ = try await bridge.machines.create(request)
            if fields.bool("setDefault") {
                try await bridge.machines.setDefault(id: request.name)
            }
            return .init(summary: "Created machine \(request.name)")
        case "machines.run":
            let name = try fields.requiredString("name")
            let create = MachineCreateRequest(name: name, resources: resources(fields))
            let request = ProcessRequest(
                resourceID: name,
                arguments: [fields.string("executable") ?? "/bin/sh"] + fields.strings("arguments"),
                environment: fields.keyValues("environment"),
                workingDirectory: fields.string("workingDirectory"),
                user: fields.string("user"),
                tty: fields.bool("tty"),
                interactive: fields.bool("interactive")
            )
            return try await process(bridge.machines.run(.init(create: create, process: request)), fields: fields)
        case "machines.list":
            return try await .init(summary: "Found \(bridge.machines.list().count) machines")
        case "machines.inspect":
            let id = try fields.requiredString("id")
            _ = try await bridge.machines.inspect(id: id)
            return .init(summary: "Inspected machine \(id)")
        case "machines.set":
            let name = try fields.requiredString("name")
            let values = Dictionary(uniqueKeysWithValues: fields.keyValues("settings").map { ($0.key, $0.value) })
            let request = MachineSetRequest(
                resources: machineSetResources(values),
                homeMount: values["homeMount"],
                nestedVirtualization: values["nestedVirtualization"].flatMap(Bool.init)
            )
            _ = try await bridge.machines.set(id: name, request: request)
            return .init(summary: "Updated machine \(name)")
        case "machines.set-default":
            let id = try fields.requiredString("id")
            try await bridge.machines.setDefault(id: id)
            return .init(summary: "Set default machine \(id)")
        case "machines.logs":
            let id = try fields.requiredString("id")
            let count = try await consume(bridge.machines.logs(id: id, options: logOptions(fields)))
            return .init(summary: "Read \(count) machine log records")
        case "machines.stop":
            let id = try fields.requiredString("id")
            return try await batch(bridge.machines.stop(ids: [id], force: false), action: "Stopped")
        case "machines.delete":
            let id = try fields.requiredString("id")
            return try await batch(bridge.machines.delete(ids: [id], force: false), action: "Deleted")
        case "system.start":
            let timeout = Int(fields.int("timeout") ?? 30)
            let result = try await bridge.system.start(.init(healthTimeoutSeconds: timeout))
            return .init(summary: "Runtime is \(result.state.rawValue)")
        case "system.stop":
            let result = try await bridge.system.stop(.init(stopActiveWorkloads: false, timeoutSeconds: 30))
            return .init(summary: "Runtime is \(result.state.rawValue)")
        case "system.status":
            let result = try await bridge.system.status()
            return .init(summary: "Runtime is \(result.state.rawValue)")
        case "system.version":
            let result = try await bridge.system.version()
            return .init(summary: "Runtime \(result.version) · API \(result.apiVersion ?? "unavailable")")
        case "system.logs":
            let count = try await consume(bridge.system.logs(logOptions(fields)))
            return .init(summary: "Read \(count) system log records")
        case "system.disk-usage":
            let result = try await bridge.system.diskUsage()
            let total = result.containersBytes + result.imagesBytes + result.volumesBytes
            return .init(summary: "Runtime uses \(total) bytes")
        case "dns.create":
            let name = try fields.requiredString("domainName")
            let addresses = fields.string("localhostAddress").map { [$0] } ?? []
            _ = try await bridge.dns.create(.init(name: name, addresses: addresses))
            return .init(summary: "Created DNS entry \(name)")
        case "dns.delete":
            return try await batch(
                bridge.dns.delete(names: [fields.requiredString("domainName")]),
                action: "Deleted"
            )
        case "dns.list":
            return try await .init(summary: "Found \(bridge.dns.list().count) DNS entries")
        case "kernel.set":
            return try await setKernel(fields)
        case "configuration.manage":
            let configuration = try await bridge.configuration.load()
            let preview = try await bridge.configuration.preview(configuration)
            return .init(summary: preview.isEmpty ? "Configuration loaded" : "Configuration preview ready")
        default:
            throw BridgeOperationDispatcherError.unsupportedOperation(draft.operationID)
        }
    }

    private func containerCreateRequest(_ fields: DraftReader) throws -> ContainerCreateRequest {
        try ContainerCreateRequest(
            name: fields.string("name") ?? "maccontainer-\(UUID().uuidString.lowercased())",
            imageReference: fields.requiredString("image"),
            arguments: fields.strings("arguments"),
            environment: fields.keyValues("environment"),
            resources: resources(fields),
            mounts: fields.mounts("mounts") + fields.mounts("volumes"),
            networks: fields.strings("networks"),
            publishedPorts: fields.portMappings("publishedPorts"),
            platform: fields.string("platform"),
            workingDirectory: fields.string("workingDirectory"),
            readOnlyRoot: fields.bool("readOnlyRootFilesystem"),
            capabilitiesToAdd: fields.strings("capabilitiesToAdd"),
            capabilitiesToDrop: fields.strings("capabilitiesToDrop"),
            temporaryFilesystems: fields.strings("temporaryFilesystems"),
            dnsServers: fields.strings("dnsServers"),
            noDNS: fields.bool("noDNS"),
            nestedVirtualization: fields.bool("nestedVirtualization")
        )
    }

    private func machineCreateRequest(_ fields: DraftReader) throws -> MachineCreateRequest {
        let homeMount = fields.string("homeMount") ?? "none"
        if homeMount != "none" {
            throw BridgeOperationDispatcherError.explicitConsentRequired("homeMount")
        }
        return try MachineCreateRequest(
            name: fields.requiredString("name"),
            imageReference: fields.string("image"),
            resources: resources(fields),
            homeMount: homeMount,
            networks: fields.strings("networks"),
            kernelIdentifier: fields.string("kernel"),
            nestedVirtualization: fields.bool("nestedVirtualization")
        )
    }

    private func resources(_ fields: DraftReader) -> RuntimeResources {
        RuntimeResources(
            cpuCount: max(1, Int(fields.int("cpus") ?? 2)),
            memoryBytes: max(268_435_456, fields.bytes("memory") ?? 2_147_483_648),
            diskBytes: fields.bytes("disk")
        )
    }

    private func machineSetResources(_ values: [String: String]) -> RuntimeResources? {
        guard let cpu = values["cpus"].flatMap(Int.init),
              let memory = values["memory"].flatMap(Int64.init)
        else { return nil }
        return .init(cpuCount: cpu, memoryBytes: memory)
    }

    private func imageTransferRequest(_ fields: DraftReader) -> ImageTransferRequest {
        .init(
            reference: fields.string("reference") ?? "",
            platform: fields.string("platform"),
            unpack: true
        )
    }

    private func logOptions(_ fields: DraftReader) -> LogOptions {
        .init(
            follow: fields.bool("follow"),
            tail: fields.int("tailLines").map(Int.init),
            timestamps: true
        )
    }

    private func copyEndpoint(_ value: String) throws -> CopyEndpoint {
        if value.hasPrefix("/") || value.hasPrefix("~") {
            return .local(URL(fileURLWithPath: value).standardizedFileURL)
        }
        let parts = value.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, String(parts[1]).hasPrefix("/") else {
            throw BridgeOperationDispatcherError.invalidField("copyEndpoint")
        }
        return .container(id: String(parts[0]), path: String(parts[1]))
    }

    private func process(
        _ session: any ProcessSession,
        fields: DraftReader
    ) async throws -> OperationDispatchResult {
        if fields.bool("detach") || fields.bool("interactive") || fields.bool("tty") {
            try await session.detach()
            return .init(summary: "Opened process session \(session.id)")
        }
        let exit = try await session.wait()
        return .init(summary: "Process exited with code \(exit.code)")
    }

    private func setKernel(_ fields: DraftReader) async throws -> OperationDispatchResult {
        let platform = fields.string("architecture") ?? "arm64"
        let force = fields.bool("force")
        let result: KernelSummary
        if fields.bool("recommended") {
            result = try await bridge.kernel.setRecommended(platform: platform, force: force)
        } else if let binary = try fields.fileURL("binary") {
            result = try await bridge.kernel.setLocalBinary(binary, platform: platform, force: force)
        } else if let archive = fields.string("archive") {
            guard !archive.hasPrefix("http://"), !archive.hasPrefix("https://") else {
                throw BridgeOperationDispatcherError.invalidField("archive")
            }
            result = try await bridge.kernel.setLocalArchive(
                URL(fileURLWithPath: archive).standardizedFileURL,
                platform: platform,
                force: force
            )
        } else {
            throw BridgeOperationDispatcherError.invalidField("kernelSource")
        }
        return .init(summary: "Installed kernel \(result.identifier)")
    }

    private func batch(_ results: [BatchItemResult], action: String) -> OperationDispatchResult {
        .init(
            summary: "\(action) \(results.count) resources",
            itemResults: results.map {
                .init(resourceID: $0.id, outcome: $0.succeeded ? .succeeded : .failed, error: $0.error)
            }
        )
    }

    private func prune(_ result: PruneResult, kind: String) -> OperationDispatchResult {
        .init(
            summary: "Pruned \(result.deletedIDs.count) \(kind); reclaimed \(result.reclaimedBytes) bytes",
            itemResults: result.deletedIDs.map { .init(resourceID: $0, outcome: .succeeded) }
        )
    }

    private func consume<Element: Sendable>(
        _ stream: AsyncThrowingStream<Element, any Error>,
        limit: Int = 10000
    ) async throws -> Int {
        var count = 0
        for try await _ in stream {
            try Task.checkCancellation()
            count += 1
            if count >= limit {
                break
            }
        }
        return count
    }
}

private struct DraftReader: Sendable {
    private let fields: [String: DraftField]

    init(_ draft: OperationDraft) {
        fields = draft.fields
    }

    func string(_ id: String) -> String? {
        guard let value = fields[id]?.value else { return nil }
        switch value {
        case let .string(value), let .path(value), let .secret(value):
            return value.isEmpty ? nil : value
        case let .integer(value): return String(value)
        case let .bytes(value): return String(value)
        case .none: return nil
        default: return nil
        }
    }

    func requiredString(_ id: String) throws -> String {
        guard let value = string(id), !value.isEmpty else {
            throw BridgeOperationDispatcherError.invalidField(id)
        }
        return value
    }

    func strings(_ id: String) -> [String] {
        guard let value = fields[id]?.value else { return [] }
        switch value {
        case let .strings(values): return values.filter { !$0.isEmpty }
        case let .string(value), let .path(value): return value.isEmpty ? [] : [value]
        case .none: return []
        default: return []
        }
    }

    func identifiers(_ singular: String, _ plural: String) -> [String] {
        let values = strings(plural)
        if !values.isEmpty {
            return values
        }
        return string(singular).map { [$0] } ?? []
    }

    func bool(_ id: String) -> Bool {
        guard let value = fields[id]?.value else { return false }
        switch value {
        case let .bool(value): return value
        case let .string(value): return Bool(value) ?? false
        default: return false
        }
    }

    func int(_ id: String) -> Int64? {
        guard let value = fields[id]?.value else { return nil }
        switch value {
        case let .integer(value), let .bytes(value): return value
        case let .duration(value): return value.seconds
        case let .string(value): return Int64(value)
        default: return nil
        }
    }

    func bytes(_ id: String) -> Int64? {
        guard let value = fields[id]?.value else { return nil }
        switch value {
        case let .bytes(value), let .integer(value): return value
        case let .string(value): return Self.parseBytes(value)
        default: return nil
        }
    }

    func keyValues(_ id: String) -> [KeyValue] {
        guard let value = fields[id]?.value else { return [] }
        switch value {
        case let .keyValues(values): return values
        case let .strings(values):
            return values.compactMap { raw in
                let parts = raw.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard let key = parts.first, !key.isEmpty else { return nil }
                return .init(key: String(key), value: parts.count == 2 ? String(parts[1]) : "")
            }
        default: return []
        }
    }

    func mounts(_ id: String) -> [Mount] {
        guard case let .mounts(values) = fields[id]?.value else { return [] }
        return values
    }

    func portMappings(_ id: String) -> [PortMapping] {
        guard case let .portMappings(values) = fields[id]?.value else { return [] }
        return values
    }

    func fileURL(_ id: String, required: Bool = false) throws -> URL? {
        guard let value = string(id) else {
            if required {
                throw BridgeOperationDispatcherError.invalidField(id)
            }
            return nil
        }
        guard !value.contains("falling back to") else { return nil }
        let url = URL(fileURLWithPath: value).standardizedFileURL
        guard url.isFileURL, url.path.hasPrefix("/") || !required else {
            throw BridgeOperationDispatcherError.invalidField(id)
        }
        return url
    }

    func requiredFileURL(_ id: String) throws -> URL {
        guard let url = try fileURL(id, required: true) else {
            throw BridgeOperationDispatcherError.invalidField(id)
        }
        return url
    }

    private static func parseBytes(_ value: String) -> Int64? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        for (suffix, multiplier): (String, Int64) in [
            ("GIB", 1_073_741_824), ("GB", 1_000_000_000),
            ("MIB", 1_048_576), ("MB", 1_000_000),
            ("KIB", 1024), ("KB", 1000)
        ] where normalized.hasSuffix(suffix) {
            let number = normalized.dropLast(suffix.count)
                .trimmingCharacters(in: .whitespaces)
            return Int64(number).map { $0 * multiplier }
        }
        return Int64(normalized)
    }
}
