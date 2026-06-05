import Foundation

// Decoded from the bundled buttons.json (Contents/Resources/buttons.json).
// Each property holds the accessible names Google Meet exposes for a control
// across supported UI languages. This file is the single source of truth.
struct ButtonLabels: Decodable {
    let moreOptions: [String]
    let manageRecording: [String]
    let subtitles: [String]
    let transcript: [String]
    let gemini: [String]
    let startRecording: [String]
    let leaveCall: [String]
    let confirmStart: [String]
    let recordingActive: [String]
    let recordingBadge: [String]
}

enum ButtonConfig {
    static let shared: ButtonLabels = load()

    private static func load() -> ButtonLabels {
        guard let url = Bundle.main.url(forResource: "buttons", withExtension: "json") else {
            let message = "FATAL: buttons.json not found in app bundle."
            Logger.log(message)
            fatalError(message)
        }

        do {
            let data = try Data(contentsOf: url)
            let labels = try JSONDecoder().decode(ButtonLabels.self, from: data)
            Logger.log("Loaded button labels from \(url.lastPathComponent).")
            return labels
        } catch {
            let message = "FATAL: failed to parse buttons.json (\(error))."
            Logger.log(message)
            fatalError(message)
        }
    }
}
