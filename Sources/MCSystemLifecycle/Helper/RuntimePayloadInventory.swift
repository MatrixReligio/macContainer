import Foundation

public enum ReviewedRuntime100Manifest {
    public static let identifier = "apple-container-1.0.0"
    public static let sourceSHA256 = "68011b13cf76a8a6345d92b3b45e19b471ca45322c67242b3bca6a2d9809afc8"

    public static let package = RuntimePackageManifest(
        runtimeVersion: "1.0.0",
        assetName: "container-1.0.0-installer-signed.pkg",
        sha256: "13f45f26da94c354adcbefe1e8f7631e7f126e93c5d4dd6a5a538aa66b4f479d",
        installerTeamID: "UPBK2H6LZM",
        signerCommonName: "Developer ID Installer: Apple Inc. - Containerization (UPBK2H6LZM)",
        receiptIdentifier: "com.apple.container-installer",
        installLocation: "/usr/local",
        payload: Runtime100PathInventory.payload
    )
}

public enum ReviewedRuntime110Manifest {
    public static let identifier = "apple-container-1.1.0"
    public static let sourceSHA256 = "e858b4c9ca48fa6ed90d512ad6bc6eee7c5ec1b2ec29102d973cec7d1bb97932"

    public static let package = RuntimePackageManifest(
        runtimeVersion: "1.1.0",
        assetName: "container-1.1.0-installer-signed.pkg",
        sha256: "0ca1c42a2269c2557efb1d82b1b38ac553e6a3a3da1b1179c439bcee1e7d6714",
        installerTeamID: "UPBK2H6LZM",
        signerCommonName: "Developer ID Installer: Apple Inc. - Containerization (UPBK2H6LZM)",
        receiptIdentifier: "com.apple.container-installer",
        installLocation: "/usr/local",
        payload: Runtime110PathInventory.payload
    )
}

private enum Runtime100PathInventory {
    static let payload: [PayloadEntry] = {
        let hashes = [
            "bin/container": "ddbdf8f48d2718761b57afd450c4b02bf9174767043526d5274f0bd6b4863e33",
            "bin/container-apiserver": "12747bbc84384a71f715068a45c6214a6d86ac26a25946c70040fa0a7e893558",
            "bin/uninstall-container.sh": "51a840ab040bec9855ac66ad7c27b3b48771f69e779cb6d614895a3185a3dbb9",
            "bin/update-container.sh": "d7c11bde8814f9ee1b6ecb27067d627cb780cc89c1ed300fc9b755c214be9dd3",
            "libexec/container/plugins/container-core-images/bin/container-core-images":
                "9147d8172f129aaf2528d5e0caf8151ef928ba28d7794b16df63534eda9d8acd",
            "libexec/container/plugins/container-core-images/config.toml":
                "89ebf5415177298d36f4c67c8c03db26fac1377b428f30a5ccf96407d8f63f9d",
            "libexec/container/plugins/container-network-vmnet/bin/container-network-vmnet":
                "6b6c69ff515e54b3773fbc3839f9396763267528878b0181485822b1e0f40140",
            "libexec/container/plugins/container-network-vmnet/config.toml":
                "7ec0d522dcf9c9bc78b1e0843916bd0a98cfec45ef5b35f04fb8407ecda3db3e",
            "libexec/container/plugins/container-runtime-linux/bin/container-runtime-linux":
                "debfe3cfd4edbe0a0a6b75264a6c50c95ab13b913f941aa7b247d94526853885",
            "libexec/container/plugins/container-runtime-linux/config.toml":
                "d609af652f3e0224cb7f0cef315f873081506d010d2d1a8ff33508980e3427a7",
            "libexec/container/plugins/machine-apiserver/bin/machine-apiserver":
                "7571277d7f5c3909758094d6e2d2514ee5b1199abff0625f589b69e45b84b44d",
            "libexec/container/plugins/machine-apiserver/config.toml":
                "819edb0d3c20517e8a56e11a9623b3804c6821d3920da3fa66d989f766103b6a",
            "libexec/container/plugins/machine-apiserver/resources/create-user.sh":
                "4f86a20d53412736a4cad54c3d511371beb70dd1156cd7991e7448885521b8cd",
            "libexec/container/plugins/machine-apiserver/resources/init":
                "77a7f83faca9f8656ef129d8f91ddc4e770c80478d07b805a2530b9a902bf15a"
        ]
        let reviewedFiles = Runtime110PathInventory.payload.filter { $0.kind == .file }
        precondition(
            hashes.count == reviewedFiles.count && Set(hashes.keys) == Set(reviewedFiles.map(\.relativePath)),
            "The reviewed Apple container 1.0.0 payload inventory must be exact"
        )
        return Runtime110PathInventory.payload.map { entry in
            guard entry.kind == .file else { return entry }
            guard let hash = hashes[entry.relativePath] else {
                preconditionFailure("Missing reviewed Apple container 1.0.0 hash for \(entry.relativePath)")
            }
            return PayloadEntry(relativePath: entry.relativePath, kind: .file, sha256: hash)
        }
    }()
}

enum Runtime110PathInventory {
    static let payload: [PayloadEntry] = [
        .init(relativePath: "bin", kind: .directory),
        .init(
            relativePath: "bin/container",
            kind: .file,
            sha256: "1286e238b3184142dabfc5f1f9092a1d09371ddc9d05f5bf80ebafbf361fe43f"
        ),
        .init(
            relativePath: "bin/container-apiserver",
            kind: .file,
            sha256: "9d44ee36f562242d9e399cab6afbdd6de3553bd8e7befb3a1d8850d17a528b53"
        ),
        .init(
            relativePath: "bin/uninstall-container.sh",
            kind: .file,
            sha256: "51a840ab040bec9855ac66ad7c27b3b48771f69e779cb6d614895a3185a3dbb9"
        ),
        .init(
            relativePath: "bin/update-container.sh",
            kind: .file,
            sha256: "d7c11bde8814f9ee1b6ecb27067d627cb780cc89c1ed300fc9b755c214be9dd3"
        ),
        .init(relativePath: "libexec", kind: .directory),
        .init(relativePath: "libexec/container", kind: .directory),
        .init(relativePath: "libexec/container/plugins", kind: .directory),
        .init(relativePath: "libexec/container/plugins/container-core-images", kind: .directory),
        .init(relativePath: "libexec/container/plugins/container-core-images/bin", kind: .directory),
        .init(
            relativePath: "libexec/container/plugins/container-core-images/bin/container-core-images",
            kind: .file,
            sha256: "1fa5d3c63e7b7c3768f5ae9287def22477b18c6e2eed5719c27f95a7c39be9d3"
        ),
        .init(
            relativePath: "libexec/container/plugins/container-core-images/config.toml",
            kind: .file,
            sha256: "89ebf5415177298d36f4c67c8c03db26fac1377b428f30a5ccf96407d8f63f9d"
        ),
        .init(relativePath: "libexec/container/plugins/container-network-vmnet", kind: .directory),
        .init(relativePath: "libexec/container/plugins/container-network-vmnet/bin", kind: .directory),
        .init(
            relativePath: "libexec/container/plugins/container-network-vmnet/bin/container-network-vmnet",
            kind: .file,
            sha256: "40a4d48c50aff5befd7743a931c78cabe1a58c8d51c49c3d760b900c3c4790e1"
        ),
        .init(
            relativePath: "libexec/container/plugins/container-network-vmnet/config.toml",
            kind: .file,
            sha256: "7ec0d522dcf9c9bc78b1e0843916bd0a98cfec45ef5b35f04fb8407ecda3db3e"
        ),
        .init(relativePath: "libexec/container/plugins/container-runtime-linux", kind: .directory),
        .init(relativePath: "libexec/container/plugins/container-runtime-linux/bin", kind: .directory),
        .init(
            relativePath: "libexec/container/plugins/container-runtime-linux/bin/container-runtime-linux",
            kind: .file,
            sha256: "49c6666c9aa2b3fbe4eb56e1153e82f2b2ce70f176cac656b85127d17e1140ad"
        ),
        .init(
            relativePath: "libexec/container/plugins/container-runtime-linux/config.toml",
            kind: .file,
            sha256: "d609af652f3e0224cb7f0cef315f873081506d010d2d1a8ff33508980e3427a7"
        ),
        .init(relativePath: "libexec/container/plugins/machine-apiserver", kind: .directory),
        .init(relativePath: "libexec/container/plugins/machine-apiserver/bin", kind: .directory),
        .init(
            relativePath: "libexec/container/plugins/machine-apiserver/bin/machine-apiserver",
            kind: .file,
            sha256: "904ed7d64842f38be4f6034ec66703771a7bc335e5efc91c6e5990921f271841"
        ),
        .init(
            relativePath: "libexec/container/plugins/machine-apiserver/config.toml",
            kind: .file,
            sha256: "819edb0d3c20517e8a56e11a9623b3804c6821d3920da3fa66d989f766103b6a"
        ),
        .init(relativePath: "libexec/container/plugins/machine-apiserver/resources", kind: .directory),
        .init(
            relativePath: "libexec/container/plugins/machine-apiserver/resources/create-user.sh",
            kind: .file,
            sha256: "4f86a20d53412736a4cad54c3d511371beb70dd1156cd7991e7448885521b8cd"
        ),
        .init(
            relativePath: "libexec/container/plugins/machine-apiserver/resources/init",
            kind: .file,
            sha256: "77a7f83faca9f8656ef129d8f91ddc4e770c80478d07b805a2530b9a902bf15a"
        )
    ]
}
