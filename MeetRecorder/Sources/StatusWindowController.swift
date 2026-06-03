import Cocoa

final class StatusWindowController: NSWindowController {
    private var instructionLabel: NSTextField!
    private var statusLabel: NSTextField!
    private var automationLabel: NSTextField!
    private var toggleButton: NSButton!
    private var grantAccessButton: NSButton!
    private var killButton: NSButton!
    private var refreshTimer: Timer?

    convenience init() {
        let w = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
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
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
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

        instructionLabel = wrappingLabel(font: .systemFont(ofSize: 13))

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)

        automationLabel = wrappingLabel(font: .systemFont(ofSize: 12))
        automationLabel.textColor = .secondaryLabelColor

        toggleButton = NSButton(checkboxWithTitle: "Auto-record meetings", target: self, action: #selector(toggleRecording))
        toggleButton.font = .systemFont(ofSize: 14)

        grantAccessButton = NSButton(title: "Open Accessibility Settings", target: self, action: #selector(requestAccessibilityAccess))
        grantAccessButton.bezelStyle = .rounded
        grantAccessButton.keyEquivalent = "\r"

        killButton = NSButton(title: "Kill bg process", target: self, action: #selector(confirmKillProcess))
        killButton.bezelStyle = .rounded

        let stack = NSStackView(views: [instructionLabel, statusLabel, toggleButton, automationLabel, grantAccessButton, killButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(greaterThanOrEqualTo: content.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            instructionLabel.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            automationLabel.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
        ])
    }

    private func wrappingLabel(font: NSFont) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = font
        label.isEditable = false
        label.isSelectable = false
        label.drawsBackground = false
        label.isBezeled = false
        return label
    }

    // MARK: - Refresh

    private func refresh() {
        let trusted = AXMeetClient.isAccessibilityTrusted(prompt: false)

        if !trusted {
            showPermissionRequest()
        } else {
            showRunningState()
        }
    }

    private func showPermissionRequest() {
        instructionLabel.isHidden = false
        grantAccessButton.isHidden = false
        statusLabel.isHidden = true
        toggleButton.isHidden = true
        automationLabel.isHidden = true
        killButton.isHidden = true

        instructionLabel.stringValue = """
        MeetRecorder needs Accessibility permission to detect Google Meet and start recordings for you.

        Click the button below, switch on MeetRecorder in the list, then come back. macOS will offer to quit & reopen the app — accept it.
        """
    }

    private func showRunningState() {
        instructionLabel.isHidden = true
        grantAccessButton.isHidden = true
        statusLabel.isHidden = false
        toggleButton.isHidden = false
        killButton.isHidden = false

        let watcher = (NSApp.delegate as? AppDelegate)?.watcher
        let browserDetected = watcher?.browserDetected ?? false
        let meetDetected = watcher?.meetDetected ?? false
        let inCall = watcher?.inCallDetected ?? false

        if inCall {
            statusLabel.stringValue = "● In a Google Meet call"
            statusLabel.textColor = .systemGreen
        } else if meetDetected {
            statusLabel.stringValue = "● Google Meet open — waiting to join the call"
            statusLabel.textColor = .systemBlue
        } else if browserDetected {
            statusLabel.stringValue = "● Browser detected — waiting for Meet"
            statusLabel.textColor = .secondaryLabelColor
        } else {
            statusLabel.stringValue = "○ No supported browser detected"
            statusLabel.textColor = .systemOrange
        }

        toggleButton.state = MeetWatcher.isRecordingEnabled ? .on : .off

        if let status = watcher?.lastAutomationStatus {
            automationLabel.isHidden = false
            automationLabel.stringValue = status
        } else {
            automationLabel.isHidden = true
        }
    }

    // MARK: - Actions

    @objc private func toggleRecording() {
        MeetWatcher.isRecordingEnabled = (toggleButton.state == .on)
        Logger.log("Auto-record \(MeetWatcher.isRecordingEnabled ? "enabled" : "disabled").")
    }

    // Opens the Accessibility pane directly. We deliberately do NOT call the
    // AXIsProcessTrustedWithOptions prompt — the running process already
    // appears in the list (it queries AX every second), and macOS shows its own
    // "quit & reopen" alert once the toggle is switched on.
    @objc private func requestAccessibilityAccess() {
        openAccessibilitySettings()
    }

    // Confirmation popup before killing the background process. Only proceeds
    // on "OK"; "Go back" closes the popup and changes nothing.
    @objc private func confirmKillProcess() {
        let alert = NSAlert()
        alert.messageText = "Kill background process?"
        alert.informativeText = """
        This stops MeetRecorder's background process completely — it will no longer watch for Google Meet or auto-start recordings, and it will not relaunch on login.

        You only need this when uninstalling the app. To use MeetRecorder again afterwards, reopen it.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Go back")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        killBackgroundProcess()
    }

    private func killBackgroundProcess() {
        Logger.log("User requested kill of background process.")
        // Unload the LaunchAgent so it won't relaunch, then quit this process.
        LaunchAgentManager.disable()
        NSApp.terminate(nil)
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
