import Foundation

public struct InstalledPackageReceipt: Equatable, Sendable {
    public let identifier: String
    public let version: String
    public let installLocation: String

    public init(identifier: String, version: String, installLocation: String) {
        self.identifier = identifier
        self.version = version
        self.installLocation = installLocation
    }
}

public protocol PackageReceiptReading: Sendable {
    func receipt(identifier: String) async throws -> InstalledPackageReceipt?
}

public struct PackageReceiptReader: Sendable {
    private let backend: any PackageReceiptReading

    public init(backend: any PackageReceiptReading) {
        self.backend = backend
    }

    public func readReviewedRuntimeReceipt(
        identifier: String = "com.apple.container-installer"
    ) async throws -> InstalledPackageReceipt? {
        guard identifier == "com.apple.container-installer" else {
            throw PackageReceiptReaderError.unapprovedIdentifier
        }
        guard let receipt = try await backend.receipt(identifier: identifier) else {
            return nil
        }
        guard receipt.identifier == identifier, receipt.installLocation == "/usr/local" else {
            throw PackageReceiptReaderError.untrustedReceipt
        }
        return receipt
    }
}

public enum PackageReceiptReaderError: Error, Equatable, Sendable {
    case unapprovedIdentifier
    case untrustedReceipt
}
