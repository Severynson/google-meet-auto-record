import ApplicationServices
import Cocoa
import Foundation

struct AXMeetSession {
    let key: String
    let app: NSRunningApplication
    let window: AXUIElement
    let title: String
}

struct AXControlTitles {
    let name: String
    let titles: [String]
}

// Control labels are loaded from the bundled buttons.json (see ButtonConfig).
// `name` is only for logging; `titles` are the accessible names matched in the AX tree.
enum AXMeetControls {
    static var moreOptions: AXControlTitles { AXControlTitles(name: "more options", titles: ButtonConfig.shared.moreOptions) }
    static var manageRecording: AXControlTitles { AXControlTitles(name: "manage recording", titles: ButtonConfig.shared.manageRecording) }
    static var subtitles: AXControlTitles { AXControlTitles(name: "subtitles checkbox", titles: ButtonConfig.shared.subtitles) }
    static var transcript: AXControlTitles { AXControlTitles(name: "transcript checkbox", titles: ButtonConfig.shared.transcript) }
    static var gemini: AXControlTitles { AXControlTitles(name: "gemini checkbox", titles: ButtonConfig.shared.gemini) }
    static var startRecording: AXControlTitles { AXControlTitles(name: "start recording", titles: ButtonConfig.shared.startRecording) }
    static var leaveCall: AXControlTitles { AXControlTitles(name: "leave call", titles: ButtonConfig.shared.leaveCall) }
    static var confirmStart: AXControlTitles { AXControlTitles(name: "confirm start", titles: ButtonConfig.shared.confirmStart) }
}

final class AXMeetClient {
    // Web content trees (once Chrome accessibility is enabled) are large and deep.
    private let maxDepth = 60
    private let maxNodes = 20000

    // Chromium-based browsers do not expose the web page's accessibility tree to AX
    // queries until an assistive client asks for it. Setting AXManualAccessibility
    // (and AXEnhancedUserInterface) on the application element turns it on, making
    // aria-labels visible as AX names. Without this, web buttons are invisible to AX.
    // Safari and Firefox expose web content natively; setting these attributes is harmless.
    private static let manualAccessibilityAttr = "AXManualAccessibility" as CFString
    private static let enhancedUIAttr = "AXEnhancedUserInterface" as CFString

    static func isAccessibilityTrusted(prompt: Bool) -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        guard prompt else { return false }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func runningBrowserApps() -> [NSRunningApplication] {
        let bundleIDs = [
            // Chrome family
            "com.google.Chrome",
            "com.google.Chrome.canary",
            "com.google.Chrome.beta",
            "com.google.Chrome.dev",
            "com.chromium.Chromium",
            // Safari
            "com.apple.Safari",
            // Firefox
            "org.mozilla.firefox",
            "org.mozilla.nightly",
            "org.mozilla.firefoxdeveloperedition",
            // Opera
            "com.operasoftware.Opera",
            // Brave
            "com.brave.Browser",
            "com.brave.Browser.beta",
            "com.brave.Browser.nightly",
            // Arc
            "company.thebrowser.Browser",
            // Comet (Perplexity)
            "ai.perplexity.comet",
            // ChatGPT Atlas
            "com.openai.atlas",
        ]

        return bundleIDs.flatMap {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0)
        }
    }

    func findMeetSessions(promptForAccessibility: Bool = false) -> [AXMeetSession] {
        guard Self.isAccessibilityTrusted(prompt: promptForAccessibility) else {
            if promptForAccessibility {
                Logger.log("Accessibility permission missing. Enable MeetRecorder in System Settings → Privacy & Security → Accessibility.")
            }
            return []
        }

        var sessions: [AXMeetSession] = []

        for app in Self.runningBrowserApps() {
            let root = AXUIElementCreateApplication(app.processIdentifier)
            Self.enableWebAccessibility(root)
            for window in arrayAttribute(root, kAXWindowsAttribute) {
                let title = stringAttribute(window, kAXTitleAttribute) ?? ""
                let key = "\(app.processIdentifier):\(title)"

                if title.localizedCaseInsensitiveContains("meet") {
                    sessions.append(AXMeetSession(key: key, app: app, window: window, title: title))
                }
            }
        }

        return sessions
    }

    private static func enableWebAccessibility(_ appElement: AXUIElement) {
        AXUIElementSetAttributeValue(appElement, manualAccessibilityAttr, kCFBooleanTrue)
        AXUIElementSetAttributeValue(appElement, enhancedUIAttr, kCFBooleanTrue)
    }

    // True once the given control is present in the window's AX tree.
    // Used to gate automation: only start once "more options" actually appears.
    func hasControl(_ control: AXControlTitles, in session: AXMeetSession) -> Bool {
        findElement(in: session.window, matching: control) != nil
    }

    func click(_ control: AXControlTitles, in session: AXMeetSession) -> String {
        session.app.activate(options: [.activateIgnoringOtherApps])
        Thread.sleep(forTimeInterval: 0.2)

        guard let element = findElement(in: session.window, matching: control) else {
            return "not_found"
        }

        guard let point = centerPoint(of: element) else {
            return "no_bounds"
        }

        let clicked = postMouseClick(at: point)
        Logger.log("AX OS click \(control.name) → \(clicked ? "ok" : "failed") at \(Int(point.x)),\(Int(point.y))")
        return clicked ? "ok" : "cg_event_failed"
    }

    func setCheckbox(_ control: AXControlTitles, in session: AXMeetSession, checked target: Bool) -> String {
        guard let element = findElement(in: session.window, matching: control) else {
            return "not_found"
        }

        if let current = boolAttribute(element, kAXValueAttribute), current == target {
            return "already_\(target)"
        }

        guard let point = centerPoint(of: element) else {
            return "no_bounds"
        }

        let clicked = postMouseClick(at: point)
        return clicked ? "toggled" : "cg_event_failed"
    }

    private func findElement(in root: AXUIElement, matching control: AXControlTitles) -> AXUIElement? {
        var visited = 0
        return findElement(in: root, matching: control, depth: 0, visited: &visited)
    }

    private func findElement(in root: AXUIElement, matching control: AXControlTitles, depth: Int, visited: inout Int) -> AXUIElement? {
        if depth > maxDepth || visited > maxNodes {
            return nil
        }
        visited += 1

        if element(root, matches: control) && centerPoint(of: root) != nil {
            return root
        }

        for child in childElements(root) {
            if let found = findElement(in: child, matching: control, depth: depth + 1, visited: &visited) {
                return found
            }
        }

        return nil
    }

    private func element(_ element: AXUIElement, matches control: AXControlTitles) -> Bool {
        let haystack = [
            stringAttribute(element, kAXTitleAttribute),
            stringAttribute(element, kAXDescriptionAttribute),
            stringAttribute(element, kAXHelpAttribute),
            stringAttribute(element, kAXValueAttribute)
        ]
        .compactMap { $0 }
        .map(normalize)

        guard !haystack.isEmpty else { return false }

        let needles = control.titles.map(normalize)
        return haystack.contains { text in
            needles.contains { needle in
                text == needle || text.contains(needle)
            }
        }
    }

    private func childElements(_ element: AXUIElement) -> [AXUIElement] {
        var children = arrayAttribute(element, kAXVisibleChildrenAttribute)
        if children.isEmpty {
            children = arrayAttribute(element, kAXChildrenAttribute)
        }
        return children
    }

    private func centerPoint(of element: AXUIElement) -> CGPoint? {
        guard let position = pointAttribute(element, kAXPositionAttribute),
              let size = sizeAttribute(element, kAXSizeAttribute),
              size.width > 0,
              size.height > 0 else {
            return nil
        }

        return CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
    }

    private func postMouseClick(at point: CGPoint) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let move = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left),
              let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
            return false
        }

        move.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.05)
        down.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.08)
        up.post(tap: .cghidEventTap)
        return true
    }

    private func arrayAttribute(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let array = value as? [AXUIElement] else {
            return []
        }
        return array
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }

        if let string = value as? String {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private func boolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }

        return (value as? NSNumber)?.boolValue
    }

    private func pointAttribute(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let axValue = value,
              CFGetTypeID(axValue) == AXValueGetTypeID() else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetValue((axValue as! AXValue), .cgPoint, &point) else {
            return nil
        }
        return point
    }

    private func sizeAttribute(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let axValue = value,
              CFGetTypeID(axValue) == AXValueGetTypeID() else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue((axValue as! AXValue), .cgSize, &size) else {
            return nil
        }
        return size
    }

    private func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
