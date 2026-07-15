import Foundation

enum Runtime110PathInventory {
    static let payload: [PayloadEntry] = directories.map {
        PayloadEntry(relativePath: $0, kind: .directory)
    } + files.map {
        PayloadEntry(relativePath: $0, kind: .file, sha256: String(repeating: "0", count: 64))
    }

    private static let directories = [
        "bin",
        "libexec",
        "libexec/container",
        "libexec/container/plugins",
        "libexec/container/plugins/container-core-images",
        "libexec/container/plugins/container-core-images/bin",
        "libexec/container/plugins/container-network-vmnet",
        "libexec/container/plugins/container-network-vmnet/bin",
        "libexec/container/plugins/container-runtime-linux",
        "libexec/container/plugins/container-runtime-linux/bin",
        "libexec/container/plugins/machine-apiserver",
        "libexec/container/plugins/machine-apiserver/bin",
        "libexec/container/plugins/machine-apiserver/resources"
    ]

    private static let files = [
        "bin/container",
        "bin/container-apiserver",
        "bin/uninstall-container.sh",
        "bin/update-container.sh",
        "libexec/container/plugins/container-core-images/bin/container-core-images",
        "libexec/container/plugins/container-core-images/config.toml",
        "libexec/container/plugins/container-network-vmnet/bin/container-network-vmnet",
        "libexec/container/plugins/container-network-vmnet/config.toml",
        "libexec/container/plugins/container-runtime-linux/bin/container-runtime-linux",
        "libexec/container/plugins/container-runtime-linux/config.toml",
        "libexec/container/plugins/machine-apiserver/bin/machine-apiserver",
        "libexec/container/plugins/machine-apiserver/config.toml",
        "libexec/container/plugins/machine-apiserver/resources/create-user.sh",
        "libexec/container/plugins/machine-apiserver/resources/init"
    ]
}
