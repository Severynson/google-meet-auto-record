import Foundation

// Decoded from the bundled buttons.json (Contents/Resources/buttons.json).
// Each property holds the accessible names Google Meet exposes for a control
// across supported UI languages. Editing buttons.json (in the .app or the
// source) changes automation targets without recompiling.
struct ButtonLabels: Decodable {
    let moreOptions: [String]
    let manageRecording: [String]
    let subtitles: [String]
    let transcript: [String]
    let gemini: [String]
    let startRecording: [String]
    let leaveCall: [String]
}

enum ButtonConfig {
    static let shared: ButtonLabels = load()

    private static func load() -> ButtonLabels {
        guard let url = Bundle.main.url(forResource: "buttons", withExtension: "json") else {
            Logger.log("ERROR: buttons.json not found in app bundle — using built-in defaults.")
            return fallback
        }

        do {
            let data = try Data(contentsOf: url)
            let labels = try JSONDecoder().decode(ButtonLabels.self, from: data)
            Logger.log("Loaded button labels from \(url.lastPathComponent).")
            return labels
        } catch {
            Logger.log("ERROR: failed to parse buttons.json (\(error)) — using built-in defaults.")
            return fallback
        }
    }

    // Mirrors buttons.json so the app still works if the file is missing/corrupt.
    private static let fallback = ButtonLabels(
        moreOptions: ["Інші опції", "More options", "Другие параметры", "Дополнительные параметры", "Ещё", "სხვა პარამეტრები", "მეტი ვარიანტი"],
        manageRecording: ["Керувати записом", "Manage recording", "Управление записью", "Управлять записью", "ჩაწერის მართვა"],
        subtitles: ["Включити субтитри в запис", "Turn on captions in the recording", "captions", "Включить субтитры в записи", "субтитры", "ჩანაწერში სუბტიტრების ჩართვა", "სუბტიტრები"],
        transcript: ["Також створити текстову версію", "Also create a transcript", "transcript", "Также создать текстовую версию", "расшифровка", "ასევე ტექსტური ვერსიის შექმნა"],
        gemini: ["Також почати створювати нотатки за допомогою Gemini", "Also start taking notes with Gemini", "Также начать создавать заметки с помощью Gemini", "ასევე Gemini-ით ჩანაწერების შექმნის დაწყება", "Gemini"],
        startRecording: ["Почати запис", "Start recording", "Начать запись", "ჩაწერის დაწყება"],
        leaveCall: ["Завершити дзвінок", "Leave call", "Покинуть звонок", "ზარის დატოვება"]
    )
}
