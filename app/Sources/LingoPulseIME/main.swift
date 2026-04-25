import Foundation
import InputMethodKit

// IMKServer reads InputMethodConnectionName and InputMethodServerControllerClass
// from the bundle's Info.plist to set up the IPC connection and controller class.
// Using initWithName:bundleIdentifier: avoids hardcoding class names here.
let connectionName = Bundle.main.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String
    ?? "com.lingopulse.ime_Connection"

let server = IMKServer(
    name: connectionName,
    bundleIdentifier: Bundle.main.bundleIdentifier ?? "com.lingopulse.ime"
)

// Keep the run loop alive; InputMethodKit uses it for IPC with text clients.
NSApplication.shared.run()
