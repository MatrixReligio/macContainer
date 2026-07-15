#!/usr/bin/swift

import Foundation

private let runtime = ["major": 1, "minor": 1, "patch": 0]
private let sourceCommit = "5973b9cc626a3e7a499bb316a958237ebe14e2ed"

private enum DefaultValue {
    case none
    case boolean(Bool)
    case integer(Int)
    case string(String)
    case strings([String])

    var json: Any {
        switch self {
        case .none: NSNull()
        case let .boolean(value): ["boolean": value]
        case let .integer(value): ["integer": value]
        case let .string(value): ["string": value]
        case let .strings(value): ["strings": value]
        }
    }
}

private struct Parameter {
    let id: String
    let cliNames: [String]
    let type: String
    let cardinality: String
    let required: Bool
    let defaultValue: DefaultValue
    let acceptedValues: [String]
    let grammar: String?
    let dependencies: [String]
    let conflicts: [String]
    let securityImpact: String?
    let capabilities: [String]

    init(
        _ id: String,
        _ cliNames: [String],
        type: String = "string",
        cardinality: String = "optional",
        required: Bool = false,
        default defaultValue: DefaultValue = .none,
        accepted: [String] = ["user-provided value accepted by Apple container 1.1.0"],
        grammar: String? = ".+",
        dependencies: [String] = [],
        conflicts: [String] = [],
        securityImpact: String? = nil,
        capabilities: [String] = []
    ) {
        self.id = id
        self.cliNames = cliNames
        self.type = type
        self.cardinality = cardinality
        self.required = required
        self.defaultValue = defaultValue
        self.acceptedValues = type == "boolean" ? [] : accepted
        self.grammar = grammar
        self.dependencies = dependencies
        self.conflicts = conflicts
        self.securityImpact = securityImpact
        self.capabilities = capabilities
    }

    init(
        _ id: String,
        _ cliNames: [String],
        type: String,
        cardinality: String,
        required: Bool,
        defaultValue: DefaultValue,
        acceptedValues: [String],
        grammar: String?,
        dependencies: [String],
        conflicts: [String],
        securityImpact: String?,
        capabilities: [String]
    ) {
        self.id = id
        self.cliNames = cliNames
        self.type = type
        self.cardinality = cardinality
        self.required = required
        self.defaultValue = defaultValue
        self.acceptedValues = acceptedValues
        self.grammar = grammar
        self.dependencies = dependencies
        self.conflicts = conflicts
        self.securityImpact = securityImpact
        self.capabilities = capabilities
    }
}

private struct Operation {
    let id: String
    let domain: String
    let nativeAction: String
    let risk: String
    let parameters: [Parameter]
}

private func flag(_ id: String, _ names: [String], default value: Bool = false, conflicts: [String] = [], capabilities: [String] = []) -> Parameter {
    Parameter(id, names, type: "boolean", default: .boolean(value), accepted: [], grammar: nil, conflicts: conflicts, capabilities: capabilities)
}

private func string(_ id: String, _ names: [String], required: Bool = false, default value: DefaultValue = .none, accepted: [String] = ["non-empty string"], grammar: String? = ".+", dependencies: [String] = [], conflicts: [String] = []) -> Parameter {
    Parameter(id, names, required: required, default: value, accepted: accepted, grammar: grammar, dependencies: dependencies, conflicts: conflicts)
}

private func repeated(_ id: String, _ names: [String], required: Bool = false, type: String = "string", default value: DefaultValue? = nil, accepted: [String] = ["one or more values accepted by Apple container 1.1.0"], grammar: String? = ".+", conflicts: [String] = []) -> Parameter {
    Parameter(id, names, type: type, cardinality: "repeated", required: required, default: value ?? (required ? .none : .strings([])), accepted: accepted, grammar: grammar, conflicts: conflicts)
}

private func integer(_ id: String, _ names: [String], required: Bool = false, default value: DefaultValue = .none, accepted: [String] = ["non-negative integer"], grammar: String = "^[0-9]+$") -> Parameter {
    Parameter(id, names, type: "integer", required: required, default: value, accepted: accepted, grammar: grammar)
}

private func enumeration(_ id: String, _ names: [String], required: Bool = false, default value: DefaultValue = .none, values: [String]) -> Parameter {
    Parameter(id, names, type: "enumeration", required: required, default: value, accepted: values, grammar: "^(\(values.joined(separator: "|")))$")
}

private func path(_ id: String, _ names: [String], required: Bool = false, default value: DefaultValue = .none, dependencies: [String] = []) -> Parameter {
    Parameter(id, names, type: "path", required: required, default: value, accepted: ["absolute path or path resolvable from the current directory"], grammar: ".+", dependencies: dependencies)
}

private let debug = flag("debug", ["--debug"])
private let outputFormat = enumeration("format", ["--format"], default: .string("table"), values: ["json", "table", "yaml", "toml"])
private let quiet = flag("quiet", ["--quiet", "-q"])

private let processParameters: [Parameter] = [
    repeated("environment", ["--env", "-e"], type: "keyValue", accepted: ["key=value", "key inherited from host"], grammar: "^[^=[:space:]]+(=.*)?$"),
    repeated("environmentFiles", ["--env-file"], type: "path", accepted: ["readable environment file"], grammar: ".+"),
    integer("groupID", ["--gid"]),
    flag("interactive", ["--interactive", "-i"]),
    flag("tty", ["--tty", "-t"]),
    string("user", ["--user", "-u"], accepted: ["user name", "numeric uid", "name or uid followed by :gid"], grammar: "^[^:[:space:]]+(:[^:[:space:]]+)?$"),
    integer("userID", ["--uid"]),
    path("workingDirectory", ["--workdir", "--cwd", "-w"]),
    repeated("ulimits", ["--ulimit"], accepted: ["type=soft", "type=soft:hard"], grammar: "^[A-Za-z0-9_-]+=[0-9]+(:[0-9]+)?$"),
]

private let resourceParameters: [Parameter] = [
    integer("cpus", ["--cpus", "-c"], accepted: ["positive integer"], grammar: "^[1-9][0-9]*$"),
    Parameter("memory", ["--memory", "-m"], type: "bytes", cardinality: "optional", required: false, defaultValue: .none, acceptedValues: ["positive byte count with optional K, M, G, T, or P suffix"], grammar: "^[1-9][0-9]*(\\.[0-9]+)?[KkMmGgTtPp]?[Bb]?$", dependencies: [], conflicts: [], securityImpact: nil, capabilities: []),
]

private let dnsParameters: [Parameter] = [
    repeated("dnsServers", ["--dns"], accepted: ["IPv4 or IPv6 address"], grammar: "^[0-9A-Fa-f:.]+$", conflicts: ["noDNS"]),
    string("dnsDomain", ["--dns-domain"], accepted: ["DNS domain name"], grammar: "^[A-Za-z0-9.-]+$", conflicts: ["noDNS"]),
    repeated("dnsOptions", ["--dns-option"], conflicts: ["noDNS"]),
    repeated("dnsSearchDomains", ["--dns-search"], accepted: ["DNS search domain"], grammar: "^[A-Za-z0-9.-]+$", conflicts: ["noDNS"]),
]

private let managementParameters: [Parameter] = [
    enumeration("architecture", ["--arch", "-a"], default: .string("host architecture"), values: ["arm64", "amd64"]),
    repeated("capabilitiesToAdd", ["--cap-add"], accepted: ["Linux capability name", "ALL"], grammar: "^(ALL|CAP_[A-Z0-9_]+|[A-Z0-9_]+)$"),
    repeated("capabilitiesToDrop", ["--cap-drop"], accepted: ["Linux capability name", "ALL"], grammar: "^(ALL|CAP_[A-Z0-9_]+|[A-Z0-9_]+)$"),
    path("containerIDFile", ["--cidfile"]),
    flag("detach", ["--detach", "-d"]),
] + dnsParameters + [
    string("entrypoint", ["--entrypoint"]),
    flag("initProcess", ["--init"]),
    string("initImage", ["--init-image"], accepted: ["OCI image reference"]),
    path("kernel", ["--kernel", "-k"]),
    repeated("labels", ["--label", "-l"], type: "keyValue", accepted: ["key=value"], grammar: "^[^=[:space:]]+=.*$"),
    repeated("mounts", ["--mount"], type: "mount", accepted: ["type=<type>,source=<source>,target=<target>[,readonly]"], grammar: ".+"),
    string("name", ["--name"], accepted: ["valid container identifier"], grammar: "^[A-Za-z0-9][A-Za-z0-9_.-]*$"),
    repeated("networks", ["--network"], accepted: ["name", "name,mac=XX:XX:XX:XX:XX:XX", "name,mtu=VALUE"], grammar: ".+"),
    flag("noDNS", ["--no-dns"], conflicts: ["dnsServers", "dnsDomain", "dnsOptions", "dnsSearchDomains"]),
    enumeration("operatingSystem", ["--os"], default: .string("linux"), values: ["linux"]),
    repeated("publishedPorts", ["--publish", "-p"], type: "portMapping", accepted: ["[host-ip:]host-port:container-port[/tcp|udp]"], grammar: ".+"),
    Parameter("platform", ["--platform"], type: "platform", cardinality: "optional", required: false, defaultValue: .none, acceptedValues: ["os/arch", "os/arch/variant"], grammar: "^[^/[:space:]]+/[^/[:space:]]+(/[^/[:space:]]+)?$", dependencies: [], conflicts: [], securityImpact: nil, capabilities: []),
    repeated("publishedSockets", ["--publish-socket"], accepted: ["host_path:container_path"], grammar: "^.+:.+$"),
    flag("readOnlyRootFilesystem", ["--read-only"]),
    flag("removeAfterStop", ["--rm", "--remove"]),
    flag("rosetta", ["--rosetta"], capabilities: ["rosetta"]),
    string("runtimeHandler", ["--runtime"], default: .string("container-runtime-linux")),
    flag("forwardSSHAgent", ["--ssh"]),
    Parameter("sharedMemorySize", ["--shm-size"], type: "bytes", cardinality: "optional", required: false, defaultValue: .none, acceptedValues: ["positive byte count with optional K, M, G, T, or P suffix"], grammar: "^[1-9][0-9]*(\\.[0-9]+)?[KkMmGgTtPp]?[Bb]?$", dependencies: [], conflicts: [], securityImpact: nil, capabilities: []),
    repeated("temporaryFilesystems", ["--tmpfs"], type: "path", accepted: ["absolute container path"], grammar: "^/.*"),
    flag("nestedVirtualization", ["--virtualization"], capabilities: ["nestedVirtualization"]),
    repeated("volumes", ["--volume", "-v"], type: "mount", accepted: ["source:target", "source:target:ro", "anonymous target path"], grammar: ".+"),
]

private let registryParameters = [
    enumeration("registryScheme", ["--scheme"], default: .string("auto"), values: ["auto", "http", "https"]),
]
private let progressParameters = [
    enumeration("progressStyle", ["--progress"], default: .string("auto"), values: ["auto", "none", "ansi", "plain", "color"]),
]
private let imageFetchParameters = [
    integer("maxConcurrentDownloads", ["--max-concurrent-downloads"], default: .integer(3), accepted: ["positive integer"], grammar: "^[1-9][0-9]*$"),
]

private func operation(_ id: String, action: String, risk: String, _ parameters: [Parameter]) -> Operation {
    Operation(id: id, domain: id.split(separator: ".").first.map(String.init)!, nativeAction: action, risk: risk, parameters: parameters + [debug])
}

private func identifier(_ id: String, _ name: String, required: Bool = true, repeated isRepeated: Bool = false, conflicts: [String] = []) -> Parameter {
    if isRepeated {
        return repeated(id, [name], required: required, accepted: ["existing identifier or unambiguous prefix"], grammar: "^[A-Za-z0-9][A-Za-z0-9_.:/@+-]*$", conflicts: conflicts)
    }
    return string(id, [name], required: required, accepted: ["existing identifier or unambiguous prefix"], grammar: "^[A-Za-z0-9][A-Za-z0-9_.:/@+-]*$", conflicts: conflicts)
}

private let operations: [Operation] = [
    operation("core.run", action: "ContainerClient.create/bootstrap", risk: "mutating", [
        string("image", ["IMAGE"], required: true, accepted: ["OCI image reference"]),
        repeated("arguments", ["ARGUMENT"], accepted: ["container init process argument"]),
    ] + processParameters + resourceParameters + managementParameters + registryParameters + progressParameters + imageFetchParameters),
    operation("core.build", action: "ContainerBuild.Builder.build", risk: "mutating", [
        repeated("architectures", ["--arch", "-a"], default: .strings(["host architecture"]), accepted: ["arm64", "amd64", "comma-separated architecture list"], grammar: ".+"),
        repeated("buildArguments", ["--build-arg"], type: "keyValue", accepted: ["key=value"], grammar: "^[^=[:space:]]+=.*$"),
        repeated("cacheImports", ["--cache-in"], accepted: ["BuildKit cache import specification"]),
        repeated("cacheExports", ["--cache-out"], accepted: ["BuildKit cache export specification"]),
        integer("cpus", ["--cpus", "-c"], default: .integer(2), accepted: ["positive integer"], grammar: "^[1-9][0-9]*$"),
        path("dockerfile", ["--file", "-f"], default: .string("Dockerfile, falling back to Containerfile")),
        repeated("labels", ["--label", "-l"], type: "keyValue", accepted: ["key=value"], grammar: "^[^=[:space:]]+=.*$"),
        Parameter("memory", ["--memory", "-m"], type: "bytes", cardinality: "optional", required: false, defaultValue: .string("2048MB"), acceptedValues: ["positive byte count with optional K, M, G, T, or P suffix"], grammar: "^[1-9][0-9]*(\\.[0-9]+)?[KkMmGgTtPp]?[Bb]?$", dependencies: [], conflicts: [], securityImpact: nil, capabilities: []),
        flag("noCache", ["--no-cache"]),
        repeated("outputs", ["--output", "-o"], type: "keyValue", default: .strings(["type=oci"]), accepted: ["type=oci", "type=tar,dest=<path>", "type=local,dest=<path>"], grammar: "^type=(oci|tar|local)(,dest=.+)?$"),
        repeated("operatingSystems", ["--os"], default: .strings(["linux"]), accepted: ["linux", "comma-separated OS list"]),
        repeated("platforms", ["--platform"], type: "platform", accepted: ["os/arch", "os/arch/variant", "comma-separated platform list"], grammar: ".+"),
        enumeration("progressStyle", ["--progress"], default: .string("auto"), values: ["auto", "plain", "tty"]),
        flag("pull", ["--pull"]),
        flag("quiet", ["--quiet", "-q"]),
        repeated("secrets", ["--secret"], accepted: ["id=<key>,env=<ENV_VAR>", "id=<key>,src=<local/path>"], grammar: "^id=[^,]+,(env|src)=.+$"),
        repeated("tags", ["--tag", "-t"], default: .strings(["generated UUID"]), accepted: ["OCI image reference"]),
        string("targetStage", ["--target"]),
        integer("vsockPort", ["--vsock-port"], default: .integer(8088), accepted: ["port number 1 through 4294967295"], grammar: "^[1-9][0-9]{0,9}$"),
        path("contextDirectory", ["CONTEXT-DIR"], default: .string(".")),
    ] + dnsParameters),

    operation("containers.create", action: "ContainerClient.create", risk: "mutating", [string("image", ["IMAGE"], required: true, accepted: ["OCI image reference"]), repeated("arguments", ["ARGUMENT"], accepted: ["container init process argument"])] + processParameters + resourceParameters + managementParameters + registryParameters + imageFetchParameters),
    operation("containers.start", action: "ContainerClient.bootstrap", risk: "mutating", [identifier("containerID", "CONTAINER"), flag("attach", ["--attach", "-a"]), flag("interactive", ["--interactive", "-i"])]),
    operation("containers.stop", action: "ContainerClient.stop", risk: "mutating", [flag("all", ["--all", "-a"], conflicts: ["containerIDs"]), Parameter("signal", ["--signal", "-s"], type: "signal", cardinality: "optional", required: false, defaultValue: .string("SIGTERM"), acceptedValues: ["POSIX signal name or number"], grammar: "^(SIG)?[A-Za-z0-9]+$", dependencies: [], conflicts: [], securityImpact: nil, capabilities: []), Parameter("timeoutSeconds", ["--time", "-t"], type: "duration", cardinality: "optional", required: false, defaultValue: .integer(5), acceptedValues: ["integer seconds greater than or equal to 0"], grammar: "^[0-9]+$", dependencies: [], conflicts: [], securityImpact: nil, capabilities: []), identifier("containerIDs", "CONTAINER", required: false, repeated: true, conflicts: ["all"])]),
    operation("containers.kill", action: "ContainerClient.kill", risk: "destructive", [flag("all", ["--all", "-a"], conflicts: ["containerIDs"]), Parameter("signal", ["--signal", "-s"], type: "signal", cardinality: "optional", required: false, defaultValue: .string("KILL"), acceptedValues: ["POSIX signal name or number"], grammar: "^(SIG)?[A-Za-z0-9]+$", dependencies: [], conflicts: [], securityImpact: nil, capabilities: []), identifier("containerIDs", "CONTAINER", required: false, repeated: true, conflicts: ["all"])]),
    operation("containers.delete", action: "ContainerClient.delete", risk: "destructive", [flag("all", ["--all", "-a"], conflicts: ["containerIDs"]), flag("force", ["--force", "-f"]), identifier("containerIDs", "CONTAINER", required: false, repeated: true, conflicts: ["all"])]),
    operation("containers.list", action: "ContainerClient.list", risk: "readOnly", [flag("all", ["--all", "-a"]), outputFormat, quiet]),
    operation("containers.exec", action: "ContainerClient.exec", risk: "mutating", [identifier("containerID", "CONTAINER"), repeated("arguments", ["ARGUMENT"], required: true, accepted: ["process executable and arguments"]), flag("detach", ["--detach", "-d"])] + processParameters),
    operation("containers.export", action: "ContainerClient.export", risk: "readOnly", [identifier("containerID", "CONTAINER"), path("output", ["--output", "-o"])]),
    operation("containers.logs", action: "ContainerClient.logs", risk: "readOnly", [identifier("containerID", "CONTAINER"), flag("boot", ["--boot"]), flag("follow", ["--follow", "-f"]), integer("tailLines", ["-n"]) ]),
    operation("containers.inspect", action: "ContainerClient.get", risk: "readOnly", [identifier("containerIDs", "CONTAINER", repeated: true)]),
    operation("containers.stats", action: "ContainerClient.stats", risk: "readOnly", [identifier("containerIDs", "CONTAINER", required: false, repeated: true), outputFormat, flag("noStream", ["--no-stream"])]),
    operation("containers.copy", action: "ContainerClient.copy", risk: "mutating", [path("source", ["SOURCE"], required: true), path("destination", ["DESTINATION"], required: true)]),
    operation("containers.prune", action: "ContainerClient.prune", risk: "destructive", []),

    operation("images.list", action: "ClientImage.list", risk: "readOnly", [outputFormat, quiet, flag("verbose", ["--verbose", "-v"])]),
    operation("images.pull", action: "ClientImage.pull", risk: "mutating", [identifier("reference", "REFERENCE")] + registryParameters + progressParameters + imageFetchParameters + [enumeration("architecture", ["--arch", "-a"], values: ["arm64", "amd64"]), string("operatingSystem", ["--os"], accepted: ["OCI operating system"]), Parameter("platform", ["--platform"], type: "platform", cardinality: "optional", required: false, defaultValue: .none, acceptedValues: ["os/arch", "os/arch/variant"], grammar: "^[^/]+/[^/]+(/[^/]+)?$", dependencies: [], conflicts: [], securityImpact: nil, capabilities: [])]),
    operation("images.push", action: "ClientImage.push", risk: "mutating", [identifier("reference", "REFERENCE")] + registryParameters + progressParameters + [enumeration("architecture", ["--arch", "-a"], values: ["arm64", "amd64"]), string("operatingSystem", ["--os"], accepted: ["OCI operating system"]), Parameter("platform", ["--platform"], type: "platform", cardinality: "optional", required: false, defaultValue: .none, acceptedValues: ["os/arch", "os/arch/variant"], grammar: "^[^/]+/[^/]+(/[^/]+)?$", dependencies: [], conflicts: [], securityImpact: nil, capabilities: [])]),
    operation("images.save", action: "ClientImage.save", risk: "readOnly", [identifier("references", "REFERENCE", repeated: true), enumeration("architecture", ["--arch", "-a"], values: ["arm64", "amd64"]), string("operatingSystem", ["--os"], accepted: ["OCI operating system"]), path("output", ["--output", "-o"]), Parameter("platform", ["--platform"], type: "platform", cardinality: "optional", required: false, defaultValue: .none, acceptedValues: ["os/arch", "os/arch/variant"], grammar: "^[^/]+/[^/]+(/[^/]+)?$", dependencies: [], conflicts: [], securityImpact: nil, capabilities: [])]),
    operation("images.load", action: "ClientImage.load", risk: "mutating", [path("input", ["--input", "-i"]), flag("force", ["--force", "-f"])]),
    operation("images.tag", action: "ClientImage.tag", risk: "mutating", [identifier("source", "SOURCE"), identifier("target", "TARGET")]),
    operation("images.delete", action: "ClientImage.delete", risk: "destructive", [flag("all", ["--all", "-a"], conflicts: ["images"]), flag("force", ["--force", "-f"]), identifier("images", "IMAGE", required: false, repeated: true, conflicts: ["all"])]),
    operation("images.prune", action: "ClientImage.prune", risk: "destructive", [flag("all", ["--all", "-a"])]),
    operation("images.inspect", action: "ClientImage.get", risk: "readOnly", [identifier("images", "IMAGE", repeated: true)]),

    operation("builder.start", action: "ContainerClient.createBuilder", risk: "mutating", [integer("cpus", ["--cpus", "-c"], default: .integer(2), accepted: ["positive integer"], grammar: "^[1-9][0-9]*$"), Parameter("memory", ["--memory", "-m"], type: "bytes", cardinality: "optional", required: false, defaultValue: .string("2048MB"), acceptedValues: ["positive byte count with optional unit suffix"], grammar: "^[1-9][0-9]*[KkMmGgTtPp]?[Bb]?$", dependencies: [], conflicts: [], securityImpact: nil, capabilities: [])] + dnsParameters),
    operation("builder.status", action: "ContainerClient.getBuilder", risk: "readOnly", [outputFormat, quiet]),
    operation("builder.stop", action: "ContainerClient.stopBuilder", risk: "mutating", []),
    operation("builder.delete", action: "ContainerClient.deleteBuilder", risk: "destructive", [flag("force", ["--force", "-f"])]),

    operation("networks.create", action: "ContainerNetworkClient.create", risk: "mutating", [string("name", ["NAME"], required: true, accepted: ["valid network name"]), flag("internal", ["--internal"]), repeated("labels", ["--label"], type: "keyValue", accepted: ["key=value"], grammar: "^[^=]+=.*$"), repeated("options", ["--option"], type: "keyValue", accepted: ["key=value"], grammar: "^[^=]+=.*$"), string("plugin", ["--plugin"], default: .string("container-network-vmnet")), string("ipv4Subnet", ["--subnet"], accepted: ["IPv4 CIDR"], grammar: "^[0-9.]+/[0-9]{1,2}$"), string("ipv6Subnet", ["--subnet-v6"], accepted: ["IPv6 CIDR"], grammar: "^[0-9A-Fa-f:]+/[0-9]{1,3}$")]),
    operation("networks.delete", action: "ContainerNetworkClient.delete", risk: "destructive", [flag("all", ["--all", "-a"], conflicts: ["networkNames"]), identifier("networkNames", "NETWORK", required: false, repeated: true, conflicts: ["all"])]),
    operation("networks.prune", action: "ContainerNetworkClient.prune", risk: "destructive", []),
    operation("networks.list", action: "ContainerNetworkClient.list", risk: "readOnly", [outputFormat, quiet]),
    operation("networks.inspect", action: "ContainerNetworkClient.inspect", risk: "readOnly", [identifier("networks", "NETWORK", repeated: true)]),

    operation("volumes.create", action: "ContainerClient.createVolume", risk: "mutating", [string("name", ["NAME"], required: true, accepted: ["valid volume name"]), repeated("labels", ["--label"], type: "keyValue", accepted: ["key=value"], grammar: "^[^=]+=.*$"), repeated("driverOptions", ["--opt"], type: "keyValue", accepted: ["size=<bytes>", "journal=ordered[:size]", "journal=writeback[:size]", "journal=journal[:size]"], grammar: "^[^=]+=.*$"), Parameter("size", ["-s"], type: "bytes", cardinality: "optional", required: false, defaultValue: .none, acceptedValues: ["at least 1 MiB with optional K, M, G, T, or P suffix"], grammar: "^[1-9][0-9]*[KkMmGgTtPp]?$", dependencies: [], conflicts: [], securityImpact: nil, capabilities: [])]),
    operation("volumes.delete", action: "ContainerClient.deleteVolume", risk: "destructive", [flag("all", ["--all", "-a"], conflicts: ["names"]), identifier("names", "VOLUME", required: false, repeated: true, conflicts: ["all"])]),
    operation("volumes.prune", action: "ContainerClient.pruneVolumes", risk: "destructive", []),
    operation("volumes.list", action: "ContainerClient.listVolumes", risk: "readOnly", [outputFormat, quiet]),
    operation("volumes.inspect", action: "ContainerClient.inspectVolumes", risk: "readOnly", [identifier("names", "VOLUME", repeated: true)]),

    operation("registries.login", action: "ClientImage.login", risk: "mutating", [string("server", ["SERVER"], required: true, accepted: ["registry host name"])] + registryParameters + [flag("passwordFromStandardInput", ["--password-stdin"]), string("username", ["--username", "-u"]), Parameter("password", ["SECURE-PROMPT"], type: "string", cardinality: "optional", required: false, defaultValue: .none, acceptedValues: ["registry credential entered securely or supplied via standard input"], grammar: ".*", dependencies: [], conflicts: [], securityImpact: "mutating", capabilities: ["secureCredentialInput"])]),
    operation("registries.logout", action: "ClientImage.logout", risk: "mutating", [string("server", ["SERVER"], required: true, accepted: ["registry host name"])]),
    operation("registries.list", action: "ClientImage.listRegistries", risk: "readOnly", [outputFormat, quiet]),

    operation("machines.create", action: "MachineClient.create", risk: "mutating", [string("image", ["IMAGE"], required: true, accepted: ["OCI image reference"]), string("name", ["--name", "-n"], accepted: ["valid machine identifier"]), flag("setDefault", ["--set-default"]), flag("noBoot", ["--no-boot"]), integer("cpus", ["--cpus"], accepted: ["positive integer"], grammar: "^[1-9][0-9]*$"), Parameter("memory", ["--memory"], type: "bytes", cardinality: "optional", required: false, defaultValue: .string("half of system memory"), acceptedValues: ["positive byte count with optional unit suffix"], grammar: "^[1-9][0-9]*[KkMmGgTtPp]?[Bb]?$", dependencies: [], conflicts: [], securityImpact: nil, capabilities: []), enumeration("homeMount", ["--home-mount"], default: .string("rw"), values: ["ro", "rw", "none"]), flag("nestedVirtualization", ["--virtualization"], capabilities: ["nestedVirtualization"]), path("kernel", ["--kernel"]), enumeration("architecture", ["--arch", "-a"], default: .string("host architecture"), values: ["arm64", "amd64"]), enumeration("operatingSystem", ["--os"], default: .string("linux"), values: ["linux"]), Parameter("platform", ["--platform"], type: "platform", cardinality: "optional", required: false, defaultValue: .none, acceptedValues: ["os/arch", "os/arch/variant"], grammar: "^[^/]+/[^/]+(/[^/]+)?$", dependencies: [], conflicts: [], securityImpact: nil, capabilities: [])] + registryParameters + progressParameters + imageFetchParameters),
    operation("machines.run", action: "MachineClient.run", risk: "mutating", [string("name", ["--name", "-n"], accepted: ["existing machine identifier"]), flag("detach", ["--detach", "-d"]), flag("root", ["--root"]), string("executable", ["EXECUTABLE"], default: .string("login shell")), repeated("arguments", ["ARGUMENT"], accepted: ["process argument"])] + processParameters),
    operation("machines.list", action: "MachineClient.list", risk: "readOnly", [enumeration("format", ["--format"], default: .string("table"), values: ["json", "table"]), quiet]),
    operation("machines.inspect", action: "MachineClient.inspect", risk: "readOnly", [identifier("id", "MACHINE", required: false)]),
    operation("machines.set", action: "MachineClient.setConfig", risk: "mutating", [identifier("name", "--name", required: false), repeated("settings", ["SETTING"], required: true, type: "keyValue", accepted: ["cpus=<number>", "memory=<size>", "home-mount=ro|rw|none", "virtualization=true|false", "kernel=<path>"], grammar: "^(cpus|memory|home-mount|virtualization|kernel)=.*$")]),
    operation("machines.set-default", action: "MachineClient.setDefault", risk: "mutating", [identifier("id", "MACHINE")]),
    operation("machines.logs", action: "MachineClient.logs", risk: "readOnly", [identifier("id", "MACHINE", required: false), flag("boot", ["--boot"]), flag("follow", ["--follow", "-f"]), integer("tailLines", ["-n"])]),
    operation("machines.stop", action: "MachineClient.stop", risk: "mutating", [identifier("id", "MACHINE", required: false)] + progressParameters),
    operation("machines.delete", action: "MachineClient.delete", risk: "destructive", [identifier("id", "MACHINE")] + progressParameters),

    operation("system.start", action: "ServiceManager.register", risk: "privileged", [path("applicationRoot", ["--app-root", "-a"], default: .string("ApplicationRoot.defaultPath")), path("installRoot", ["--install-root"], default: .string("InstallRoot.defaultPath")), path("logRoot", ["--log-root"]), Parameter("kernelInstall", ["--enable-kernel-install", "--disable-kernel-install"], type: "boolean", cardinality: "optional", required: false, defaultValue: .none, acceptedValues: [], grammar: nil, dependencies: [], conflicts: [], securityImpact: "privileged", capabilities: []), Parameter("timeout", ["--timeout"], type: "duration", cardinality: "optional", required: false, defaultValue: .integer(60), acceptedValues: ["positive number of seconds"], grammar: "^[0-9]+(\\.[0-9]+)?$", dependencies: [], conflicts: [], securityImpact: nil, capabilities: [])]),
    operation("system.stop", action: "ServiceManager.unregister", risk: "privileged", [string("servicePrefix", ["--prefix", "-p"], default: .string("com.apple.container."))]),
    operation("system.status", action: "ClientHealthCheck.ping", risk: "readOnly", [string("servicePrefix", ["--prefix", "-p"], default: .string("com.apple.container.")), outputFormat]),
    operation("system.version", action: "ClientHealthCheck.version", risk: "readOnly", [outputFormat]),
    operation("system.logs", action: "OSLogStore.entries", risk: "readOnly", [flag("follow", ["--follow", "-f"]), Parameter("last", ["--last"], type: "duration", cardinality: "optional", required: false, defaultValue: .string("5m"), acceptedValues: ["duration in seconds, minutes, hours, or days"], grammar: "^[0-9]+[mhd]?$", dependencies: [], conflicts: [], securityImpact: nil, capabilities: [])]),
    operation("system.disk-usage", action: "ContainerClient.diskUsage", risk: "readOnly", [outputFormat]),

    operation("dns.create", action: "DNSService.create", risk: "privileged", [string("domainName", ["DOMAIN"], required: true, accepted: ["local DNS domain"], grammar: "^[A-Za-z0-9.-]+$"), string("localhostAddress", ["--localhost"], accepted: ["IPv4 or IPv6 address"], grammar: "^[0-9A-Fa-f:.]+$")]),
    operation("dns.delete", action: "DNSService.delete", risk: "privileged", [string("domainName", ["DOMAIN"], required: true, accepted: ["configured local DNS domain"], grammar: "^[A-Za-z0-9.-]+$")]),
    operation("dns.list", action: "DNSService.list", risk: "readOnly", [outputFormat, quiet]),
    operation("kernel.set", action: "ClientKernel.installKernel", risk: "privileged", [enumeration("architecture", ["--arch"], default: .string("host architecture"), values: ["amd64", "arm64"]), path("binary", ["--binary"], dependencies: ["recommended=false"]), flag("force", ["--force"]), flag("recommended", ["--recommended"], conflicts: ["architecture", "binary", "archive"]), string("archive", ["--tar"], accepted: ["local tar archive path", "remote tar archive URL"], dependencies: ["binary"], conflicts: ["recommended"])]),
    operation("configuration.manage", action: "ConfigurationLoader.load", risk: "readOnly", [enumeration("format", ["--format"], default: .string("toml"), values: ["json", "toml"])]),
]

private func parameterJSON(_ parameter: Parameter, operation: Operation) -> [String: Any] {
    let key = "parameter.\(operation.id).\(parameter.id)"
    return [
        "id": parameter.id,
        "cliNames": parameter.cliNames,
        "valueType": parameter.type,
        "cardinality": parameter.cardinality,
        "required": parameter.required,
        "upstreamDefault": parameter.defaultValue.json,
        "acceptedValues": parameter.acceptedValues,
        "grammar": parameter.grammar ?? NSNull(),
        "dependencies": parameter.dependencies,
        "conflicts": parameter.conflicts,
        "availability": [
            "minimumRuntime": runtime,
            "minimumMacOSMajor": 26,
            "requiresAppleSilicon": true,
            "requiredCapabilities": [operation.id] + parameter.capabilities,
        ],
        "securityImpact": parameter.securityImpact ?? operation.risk,
        "labelKey": "\(key).label",
        "conciseHelpKey": "\(key).concise",
        "detailedHelpKey": "\(key).detail",
        "validationErrorKey": "\(key).validation",
        "recoveryKey": "\(key).recovery",
    ]
}

let operationJSON: [[String: Any]] = operations.map { operation in
    [
        "id": operation.id,
        "domain": operation.domain,
        "nativeAction": operation.nativeAction,
        "risk": operation.risk,
        "parameters": operation.parameters.map { parameterJSON($0, operation: operation) },
    ]
}

let root: [String: Any] = [
    "schemaVersion": 1,
    "runtimeVersion": runtime,
    "sourceCommit": sourceCommit,
    "operations": operationJSON,
]

guard operations.count == 61 else {
    fatalError("Expected 61 operations, found \(operations.count)")
}

let outputURL = URL(fileURLWithPath: "Sources/MCContracts/Resources/apple-container-1.1.0.json")
let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
try (data + Data("\n".utf8)).write(to: outputURL, options: .atomic)
print("Generated \(outputURL.path) with \(operations.count) operations")
