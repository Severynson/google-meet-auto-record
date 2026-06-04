import ApplicationServices
import Cocoa
import Foundation

struct AXMeetSession {
    let key: String
    let app: NSRunningApplication
    let root: AXUIElement
    let window: AXUIElement
    let title: String
}

struct AXControlTitles {
    let name: String
    let titles: [String]
    let kind: AXControlKind
}

enum AXControlKind {
    case popupButton
    case menuItem
    case checkbox
    case button
}

private struct AXElementMatch {
    let element: AXUIElement
    let source: String
    let depth: Int
    let visited: Int
}

// Control labels are loaded from the bundled buttons.json (see ButtonConfig).
// `name` is only for logging; `titles` are the accessible names matched in the AX tree.
enum AXMeetControls {
    static var moreOptions: AXControlTitles { AXControlTitles(name: "more options", titles: ButtonConfig.shared.moreOptions, kind: .popupButton) }
    static var manageRecording: AXControlTitles { AXControlTitles(name: "manage recording", titles: ButtonConfig.shared.manageRecording, kind: .menuItem) }
    static var subtitles: AXControlTitles { AXControlTitles(name: "subtitles checkbox", titles: ButtonConfig.shared.subtitles, kind: .checkbox) }
    static var transcript: AXControlTitles { AXControlTitles(name: "transcript checkbox", titles: ButtonConfig.shared.transcript, kind: .checkbox) }
    static var gemini: AXControlTitles { AXControlTitles(name: "gemini checkbox", titles: ButtonConfig.shared.gemini, kind: .checkbox) }
    static var startRecording: AXControlTitles { AXControlTitles(name: "start recording", titles: ButtonConfig.shared.startRecording, kind: .button) }
    static var leaveCall: AXControlTitles { AXControlTitles(name: "leave call", titles: ButtonConfig.shared.leaveCall, kind: .button) }
    static var confirmStart: AXControlTitles { AXControlTitles(name: "confirm start", titles: ButtonConfig.shared.confirmStart, kind: .button) }
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
                let key = "\(app.processIdentifier):\(Self.sessionIdentity(from: title))"

                if title.localizedCaseInsensitiveContains("meet") {
                    sessions.append(AXMeetSession(key: key, app: app, root: root, window: window, title: title))
                }
            }
        }

        return sessions
    }

    private static func enableWebAccessibility(_ appElement: AXUIElement) {
        AXUIElementSetAttributeValue(appElement, manualAccessibilityAttr, kCFBooleanTrue)
        AXUIElementSetAttributeValue(appElement, enhancedUIAttr, kCFBooleanTrue)
    }

    private static func sessionIdentity(from title: String) -> String {
        let separators = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted
        for token in title.lowercased().components(separatedBy: separators) {
            if token.range(of: #"^[a-z]{3}-[a-z]{4}-[a-z]{3}$"#, options: .regularExpression) != nil {
                return "code:\(token)"
            }
        }
        return "title:\(title)"
    }

    // True once the given control is present in the window's AX tree.
    // Used to gate automation: only start once "more options" actually appears.
    func hasControl(_ control: AXControlTitles, in session: AXMeetSession) -> Bool {
        findElement(matching: control, in: session) != nil
    }

    func isRecordingActive(in session: AXMeetSession) -> Bool {
        if normalize(session.title).contains("recording") {
            Logger.log("Recording already active by window title sessionKey='\(session.key)' title='\(session.title)'")
            return true
        }

        guard let match = findRecordingStatus(in: session) else {
            return false
        }

        Logger.log("Recording already active by AX status sessionKey='\(session.key)' \(describe(match, session: session))")
        return true
    }

    func click(_ control: AXControlTitles, in session: AXMeetSession) -> String {
        focus(session)

        guard let match = findElement(matching: control, in: session) else {
            Logger.log("AX match \(control.name) → not_found session='\(session.title)'")
            return "not_found"
        }
        let element = match.element

        if press(element) {
            Logger.log("AX press \(control.name) → ok \(describe(match, session: session))")
            return "ok"
        }

        Logger.log("AX press \(control.name) → failed \(describe(match, session: session))")
        return "ax_press_failed"
    }

    func setCheckbox(_ control: AXControlTitles, in session: AXMeetSession, checked target: Bool) -> String {
        focus(session)

        guard let match = findElement(matching: control, in: session) else {
            Logger.log("AX match \(control.name) checkbox → not_found session='\(session.title)'")
            return "not_found"
        }
        let element = match.element

        if let current = boolAttribute(element, kAXValueAttribute), current == target {
            Logger.log("AX checkbox \(control.name) already_\(target) \(describe(match, session: session))")
            return "already_\(target)"
        }

        if press(element) {
            Logger.log("AX press \(control.name) checkbox → toggled \(describe(match, session: session))")
            return "toggled"
        }

        Logger.log("AX press \(control.name) checkbox → failed \(describe(match, session: session))")
        return "ax_press_failed"
    }

    private func focus(_ session: AXMeetSession) {
        session.app.activate(options: [.activateIgnoringOtherApps])
        AXUIElementPerformAction(session.window, kAXRaiseAction as CFString)
        Thread.sleep(forTimeInterval: 0.2)
    }

    private func findElement(matching control: AXControlTitles, in session: AXMeetSession) -> AXElementMatch? {
        let frame = rect(of: session.window)?.insetBy(dx: -200, dy: -200)
        if let match = findElement(in: session.window, matching: control, source: "window", allowedFrame: nil) {
            return match
        }
        return findElement(in: session.root, matching: control, source: "appRoot", allowedFrame: frame)
    }

    private func findElement(in root: AXUIElement, matching control: AXControlTitles, source: String, allowedFrame: CGRect? = nil) -> AXElementMatch? {
        var visited = 0
        return findElement(in: root, matching: control, source: source, allowedFrame: allowedFrame, depth: 0, visited: &visited)
    }

    private func findRecordingStatus(in session: AXMeetSession) -> AXElementMatch? {
        let frame = rect(of: session.window)?.insetBy(dx: -200, dy: -200)
        if let match = findText(in: session.window, matching: Self.recordingStatusTexts, source: "window", allowedFrame: nil) {
            return match
        }
        return findText(in: session.root, matching: Self.recordingStatusTexts, source: "appRoot", allowedFrame: frame)
    }

    private static let recordingStatusTexts = [
        "This meeting is being recorded",
        "Meeting is being recorded",
        "Ця зустріч записується",
        "Зустріч записується",
        "Эта встреча записывается",
        "Идет запись встречи",
        "Встреча записывается"
    ]

    private func findText(in root: AXUIElement, matching texts: [String], source: String, allowedFrame: CGRect? = nil) -> AXElementMatch? {
        var visited = 0
        return findText(in: root, matching: texts.map(normalize), source: source, allowedFrame: allowedFrame, depth: 0, visited: &visited)
    }

    private func findText(in root: AXUIElement, matching needles: [String], source: String, allowedFrame: CGRect?, depth: Int, visited: inout Int) -> AXElementMatch? {
        if depth > maxDepth || visited > maxNodes {
            return nil
        }
        visited += 1

        let haystack = matchTexts(root).map(normalize)
        if haystack.contains(where: { text in needles.contains(where: { text.contains($0) }) }) {
            if let point = centerPoint(of: root), allowedFrame != nil, allowedFrame?.contains(point) != true {
                // Browser root nodes can expose combined text outside our window frame.
                // Ignore that node but keep searching its children for a precise match.
            } else {
                return AXElementMatch(element: root, source: source, depth: depth, visited: visited)
            }
        }

        for child in childElements(root) {
            if let found = findText(in: child, matching: needles, source: source, allowedFrame: allowedFrame, depth: depth + 1, visited: &visited) {
                return found
            }
        }

        return nil
    }

    private func findElement(in root: AXUIElement, matching control: AXControlTitles, source: String, allowedFrame: CGRect?, depth: Int, visited: inout Int) -> AXElementMatch? {
        if depth > maxDepth || visited > maxNodes {
            return nil
        }
        visited += 1

        if element(root, matches: control), actionNames(root).contains(kAXPressAction as String), let point = centerPoint(of: root) {
            if allowedFrame == nil || allowedFrame?.contains(point) == true {
                return AXElementMatch(element: root, source: source, depth: depth, visited: visited)
            }
        }

        for child in childElements(root) {
            if let found = findElement(in: child, matching: control, source: source, allowedFrame: allowedFrame, depth: depth + 1, visited: &visited) {
                return found
            }
        }

        return nil
    }

    private func element(_ element: AXUIElement, matches control: AXControlTitles) -> Bool {
        guard roleAllowed(element, for: control) else {
            return false
        }

        let rawTexts = matchTexts(element)
        guard !isBrowserChromeNoise(rawTexts) else {
            return false
        }

        let haystack = rawTexts.map(normalize)

        guard !haystack.isEmpty else { return false }

        let needles = control.titles.map(normalize)
        return haystack.contains { text in
            needles.contains { needle in
                if requiresExactText(control) {
                    return text == needle
                }
                return text == needle || text.contains(needle)
            }
        }
    }

    private func requiresExactText(_ control: AXControlTitles) -> Bool {
        control.kind == .button
    }

    private func roleAllowed(_ element: AXUIElement, for control: AXControlTitles) -> Bool {
        let role = stringAttribute(element, kAXRoleAttribute) ?? ""

        switch control.kind {
        case .popupButton:
            return role == kAXPopUpButtonRole as String || role == kAXButtonRole as String
        case .menuItem:
            return role == kAXMenuItemRole as String
        case .checkbox:
            return role == kAXCheckBoxRole as String
        case .button:
            return role == kAXButtonRole as String
        }
    }

    private func matchTexts(_ element: AXUIElement) -> [String] {
        [
            stringAttribute(element, kAXTitleAttribute),
            stringAttribute(element, kAXDescriptionAttribute),
            stringAttribute(element, kAXHelpAttribute),
            stringAttribute(element, kAXValueAttribute)
        ]
        .compactMap { $0 }
    }

    private func isBrowserChromeNoise(_ texts: [String]) -> Bool {
        let combined = normalize(texts.joined(separator: " "))
        let blocked = [
            "bookmark",
            "unnamed bookmark",
            "http://",
            "https://",
            "chrome://",
            "gemini.google.com",
            "meet.google.com"
        ]
        return blocked.contains { combined.contains($0) }
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

    private func rect(of element: AXUIElement) -> CGRect? {
        guard let position = pointAttribute(element, kAXPositionAttribute),
              let size = sizeAttribute(element, kAXSizeAttribute),
              size.width > 0,
              size.height > 0 else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    private func press(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
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

    private func describe(_ match: AXElementMatch, session: AXMeetSession) -> String {
        let element = match.element
        let role = stringAttribute(element, kAXRoleAttribute) ?? "unknown"
        let subrole = stringAttribute(element, kAXSubroleAttribute) ?? ""
        let title = clean(stringAttribute(element, kAXTitleAttribute))
        let desc = clean(stringAttribute(element, kAXDescriptionAttribute))
        let help = clean(stringAttribute(element, kAXHelpAttribute))
        let value = clean(stringAttribute(element, kAXValueAttribute))
        let enabled = boolAttribute(element, kAXEnabledAttribute).map(String.init) ?? "unknown"
        let actions = actionNames(element).joined(separator: ",")
        let elementFrame = format(rect(of: element))
        let windowFrame = format(rect(of: session.window))

        return "[session:'\(clean(session.title) ?? "")' source:\(match.source) depth:\(match.depth) visited:\(match.visited) role:\(role) subrole:\(subrole) title:'\(title ?? "")' desc:'\(desc ?? "")' help:'\(help ?? "")' value:'\(value ?? "")' enabled:\(enabled) actions:\(actions) frame:\(elementFrame) windowFrame:\(windowFrame)]"
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

    private func actionNames(_ element: AXUIElement) -> [String] {
        var value: CFArray?
        guard AXUIElementCopyActionNames(element, &value) == .success,
              let actions = value as? [String] else {
            return []
        }
        return actions
    }

    private func format(_ rect: CGRect?) -> String {
        guard let rect else { return "none" }
        return "\(Int(rect.origin.x)),\(Int(rect.origin.y)),\(Int(rect.width))x\(Int(rect.height))"
    }

    private func clean(_ value: String?) -> String? {
        value?
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "'", with: "\\'")
    }

    private func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
