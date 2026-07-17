#!/usr/bin/swift
import CryptoKit
import Foundation

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("Sparkle signature verification FAIL: \(message)\n".utf8))
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count == 4 else { fail("usage: verify-sparkle-signature.swift public-key signature file") }
guard let publicData = Data(base64Encoded: arguments[1]), publicData.count == 32 else {
    fail("invalid Ed25519 public key")
}

guard let signature = Data(base64Encoded: arguments[2]), signature.count == 64 else {
    fail("invalid Ed25519 signature")
}

guard let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicData) else {
    fail("public key cannot be loaded")
}

let payload = try Data(contentsOf: URL(fileURLWithPath: arguments[3]), options: [.mappedIfSafe])
guard publicKey.isValidSignature(signature, for: payload) else { fail("signature does not match payload") }
print("Sparkle signature verification PASS")
