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

enum AXMeetControls {
    static let moreOptions = AXControlTitles(
        name: "more options",
        titles: [
            "More options", "More", "Options",
            "Więcej opcji", "Więcej",
            "Більше параметрів", "Інші параметри",
            "Дополнительные параметры", "Ещё",
            "Más opciones", "Plus d'options", "Weitere Optionen",
            "Mais opções", "Altre opzioni", "Meer opties",
            "その他のオプション", "更多选项", "更多選項"
        ]
    )

    static let startRecording = AXControlTitles(
        name: "start recording",
        titles: [
            "Start recording", "Record meeting", "Recording",
            "Rozpocznij nagrywanie", "Nagrywanie",
            "Почати запис", "Запис",
            "Начать запись", "Запись",
            "Iniciar grabación", "Grabación",
            "Démarrer l’enregistrement", "Démarrer l'enregistrement", "Enregistrement",
            "Aufzeichnung starten", "Aufzeichnen",
            "Iniciar gravação", "Gravação",
            "Avvia registrazione", "Registrazione",
            "Opname starten", "Opnemen"
        ]
    )

    static let endCall = AXControlTitles(
        name: "active meeting marker",
        titles: [
            "Leave call", "End call", "Leave",
            "Opuść rozmowę", "Zakończ połączenie", "Rozłącz",
            "Завершити виклик", "Покинути дзвінок",
            "Завершить вызов", "Выйти из вызова",
            "Salir de la llamada", "Quitter l’appel", "Quitter l'appel",
            "Anruf verlassen", "Sair da chamada",
            "Abbandona chiamata", "Gesprek verlaten"
        ]
    )

    static let subtitles = AXControlTitles(
        name: "subtitles checkbox",
        titles: [
            "captions", "subtitles", "record captions", "include captions",
            "napisy", "podpisy", "transkrypcja napisów",
            "субтитри", "субтитры",
            "subtítulos", "sous-titres", "untertitel",
            "legendas", "sottotitoli", "ondertiteling"
        ]
    )

    static let transcript = AXControlTitles(
        name: "transcript checkbox",
        titles: [
            "transcript", "transcription", "start a transcript",
            "transkrypcja", "transkrypt",
            "стенограма", "транскрипція", "расшифровка", "транскрипция",
            "transcripción", "transcription", "transkript",
            "transcrição", "trascrizione"
        ]
    )

    static let gemini = AXControlTitles(
        name: "gemini checkbox",
        titles: [
            "Gemini", "Take notes with Gemini", "notes with Gemini",
            "notatki Gemini", "rób notatki z Gemini",
            "нотатки Gemini", "заметки Gemini",
            "notas con Gemini", "notes avec Gemini",
            "Notizen mit Gemini", "notas com Gemini",
            "note con Gemini"
        ]
    )
}

final class AXMeetClient {
    private let maxDepth = 28
    private let maxNodes = 5000

    static func isAccessibilityTrusted(prompt: Bool) -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        guard prompt else { return false }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func runningChromeApps() -> [NSRunningApplication] {
        let bundleIDs = [
            "com.google.Chrome",
            "com.google.Chrome.canary",
            "com.google.Chrome.beta",
            "com.google.Chrome.dev",
            "com.chromium.Chromium"
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

        for app in Self.runningChromeApps() {
            let root = AXUIElementCreateApplication(app.processIdentifier)
            for window in arrayAttribute(root, kAXWindowsAttribute) {
                let title = stringAttribute(window, kAXTitleAttribute) ?? ""
                let key = "\(app.processIdentifier):\(title)"

                if title.localizedCaseInsensitiveContains("meet") || findElement(in: window, matching: AXMeetControls.endCall) != nil {
                    sessions.append(AXMeetSession(key: key, app: app, window: window, title: title))
                }
            }
        }

        return sessions
    }

    func isMeetingActive(_ session: AXMeetSession) -> Bool {
        findElement(in: session.window, matching: AXMeetControls.endCall) != nil
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
