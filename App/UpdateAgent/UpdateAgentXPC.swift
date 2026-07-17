import Foundation

@objc protocol UpdateAgentStatusXPC {
    func publishStatus(_ encodedStatus: Data, withReply reply: @escaping (Bool) -> Void)
    func submitCandidate(_ encodedCandidate: Data, withReply reply: @escaping (Bool) -> Void)
}

enum UpdateAgentXPCIdentity {
    static let serviceName = "container.matrixreligio.com.update-status"
}
