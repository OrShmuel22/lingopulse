import ApplicationServices

struct Selection {
    let text: String
    let appName: String
    let element: AXUIElement?

    var appKind: AppKind { AppKind.fromAppName(appName) }
}
