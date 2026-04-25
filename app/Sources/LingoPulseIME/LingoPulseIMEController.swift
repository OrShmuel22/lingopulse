import Foundation
import InputMethodKit

// LingoPulseIMEController is the input method controller skeleton.
// Phase 1: registers with InputMethodKit; no keystroke handling yet.
// Phase 2 will add real correction logic.
@objc(LingoPulseIMEController)
final class LingoPulseIMEController: IMKInputController {

    // MARK: - Lifecycle

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
    }

    // MARK: - IMKStateSetting (stubs)

    override func activateServer(_ sender: Any!) {
        // Phase 2: set up session state.
    }

    override func deactivateServer(_ sender: Any!) {
        // Phase 2: tear down session state.
    }

    // MARK: - IMKServerInput (stubs)

    override func inputText(_ string: String!, client sender: Any!) -> Bool {
        // Phase 2: intercept keystrokes and queue correction.
        return false  // pass through to the active app
    }

    override func commitComposition(_ sender: Any!) {
        // Phase 2: flush pending composition to the client.
    }
}
