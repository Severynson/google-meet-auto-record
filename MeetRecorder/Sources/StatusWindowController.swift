import Cocoa

final class StatusWindowController: NSWindowController {
    private var chromeStatusLabel: NSTextField!
    private var toggleButton: NSButton!
    private var refreshTimer: Timer?

    convenience init() {
        let w = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
            styleMask: [.titled, .closable, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        w.title = "MeetRecorder"
        w.isFloatingPanel = true
        w.hidesOnDeactivate = false
        w.center()
        self.init(window: w)
        buildUI()
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    override func close() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        super.close()
    }

    // MARK: - UI

    private func buildUI() {
        guard let content = window?.contentView else { return }

        chromeStatusLabel = NSTextField(labelWithString: "")
        chromeStatusLabel.font = .systemFont(ofSize: 12)
        chromeStatusLabel.textColor = .secondaryLabelColor

        toggleButton = NSButton(checkboxWithTitle: "Auto-record meetings", target: self, action: #selector(toggleRecording))
        toggleButton.font = .systemFont(ofSize: 14)

        let divider = NSBox()
        divider.boxType = .separator

        let quitBtn = NSButton(title: "Quit", target: NSApp, action: #selector(NSApp.terminate(_:)))
        quitBtn.bezelStyle = .rounded

        let bottomRow = NSStackView(views: [NSView(), quitBtn])
        bottomRow.orientation = .horizontal

        let stack = NSStackView(views: [chromeStatusLabel, divider, toggleButton, NSView(), bottomRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            divider.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            bottomRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
        ])
    }

    // MARK: - Refresh

    private func refresh() {
        let watcher = (NSApp.delegate as? AppDelegate)?.watcher
        let detected = watcher?.chromeDetected ?? false

        chromeStatusLabel.stringValue = detected
            ? "● Chrome connected on port 9222"
            : "○ Chrome not detected — open via wrapper app"
        chromeStatusLabel.textColor = detected ? .systemGreen : .systemOrange

        toggleButton.state = MeetWatcher.isRecordingEnabled ? .on : .off
    }

    // MARK: - Actions

    @objc private func toggleRecording() {
        MeetWatcher.isRecordingEnabled = (toggleButton.state == .on)
        Logger.log("Auto-record \(MeetWatcher.isRecordingEnabled ? "enabled" : "disabled").")
    }
}
