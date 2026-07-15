import Foundation

public enum ContractRepositoryError: Error, Equatable {
    case unsupportedVersion(RuntimeVersion)
    case missingBundledResource(String)
}

public enum ContractRepository {
    public static func decode(_ data: Data) throws -> UpstreamContract {
        try JSONDecoder().decode(UpstreamContract.self, from: data)
    }

    public static func bundled(version: RuntimeVersion) throws -> UpstreamContract {
        guard version == RuntimeVersion(major: 1, minor: 1, patch: 0) else {
            throw ContractRepositoryError.unsupportedVersion(version)
        }

        let name = "apple-container-\(version.description)"
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw ContractRepositoryError.missingBundledResource("\(name).json")
        }

        return try decode(Data(contentsOf: url))
    }
}
