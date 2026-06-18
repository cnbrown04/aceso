import Foundation
import Testing
import WhoopSDK
@testable import RemoteActionsAddon

@Test func rejectsInvalidEnvelopeSignature() {
    let envelope = RemoteCommandEnvelope(payload: "e30", signature: "bad")
    let cmd = CommandEnvelopeVerifier.verify(envelope: envelope, secret: "dev-api-key")
    #expect(cmd == nil)
}

@Test func rejectsDisabledRemoteActions() {
    let command = RemoteCommand(
        commandID: "1",
        type: "haptic.stop",
        params: [:],
        expiresAt: Date().addingTimeInterval(60)
    )
    let result = RemoteCommandExecutor().execute(
        command,
        whoop: WhoopBLEClient(family: .whoop4),
        remoteActionsEnabled: false
    )
    if case .rejected = result {
        #expect(Bool(true))
    } else {
        Issue.record("expected rejected")
    }
}
