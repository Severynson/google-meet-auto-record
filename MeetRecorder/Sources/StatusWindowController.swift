import Cocoa

final class StatusWindowController: NSWindowController {
    private var chromeStatusLabel: NSTextField!
    private var toggleButton: NSButton!
    private var grantAccessButton: NSButton!
    private var reopenButton: NSButton!
    private var refreshTimer: Timer?
    private var requestedAccessibilityAccess = false
    private var restartAlertShown = false

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

        grantAccessButton = NSButton(title: "Grant Access", target: self, action: #selector(requestAccessibilityAccess))
        grantAccessButton.bezelStyle = .rounded

        reopenButton = NSButton(title: "Reopen App", target: self, action: #selector(reopenApp))
        reopenButton.bezelStyle = .rounded

        let divider = NSBox()
        divider.boxType = .separator

        let quitBtn = NSButton(title: "Quit", target: NSApp, action: #selector(NSApp.terminate(_:)))
        quitBtn.bezelStyle = .rounded

        let bottomRow = NSStackView(views: [grantAccessButton, reopenButton, NSView(), quitBtn])
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
        let chromeDetected = watcher?.chromeDetected ?? false
        let meetDetected = watcher?.meetDetected ?? false
        let accessibilityTrusted = AXMeetClient.isAccessibilityTrusted(prompt: false)

        if !accessibilityTrusted {
            chromeStatusLabel.stringValue = requestedAccessibilityAccess
                ? "○ Enable access, then click Reopen App"
                : "○ Accessibility permission required"
            chromeStatusLabel.textColor = .systemOrange
        } else if meetDetected {
            chromeStatusLabel.stringValue = "● Google Meet detected via Accessibility"
            chromeStatusLabel.textColor = .systemGreen
        } else if chromeDetected {
            chromeStatusLabel.stringValue = "● Chrome detected — waiting for Meet"
            chromeStatusLabel.textColor = .secondaryLabelColor
        } else {
            chromeStatusLabel.stringValue = "○ Chrome not detected"
            chromeStatusLabel.textColor = .systemOrange
        }

        grantAccessButton.isHidden = accessibilityTrusted
        reopenButton.isHidden = accessibilityTrusted && !requestedAccessibilityAccess
        toggleButton.state = MeetWatcher.isRecordingEnabled ? .on : .off

        if accessibilityTrusted && requestedAccessibilityAccess && !restartAlertShown {
            restartAlertShown = true
            showRestartRequiredAlert()
        }
    }

    // MARK: - Actions

    @objc private func toggleRecording() {
        MeetWatcher.isRecordingEnabled = (toggleButton.state == .on)
        Logger.log("Auto-record \(MeetWatcher.isRecordingEnabled ? "enabled" : "disabled").")
    }

    @objc private func requestAccessibilityAccess() {
        requestedAccessibilityAccess = true
        _ = AXMeetClient.isAccessibilityTrusted(prompt: true)
        openAccessibilitySettings()
        refresh()
    }

    @objc private func reopenApp() {
        (NSApp.delegate as? AppDelegate)?.reopenApp()
    }

    private func showRestartRequiredAlert() {
        let alert = NSAlert()
        alert.messageText = "Reopen MeetRecorder?"
        alert.informativeText = "Accessibility access was granted. Reopen the app so the running process starts using the new permission."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Reopen")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            reopenApp()
        }
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
