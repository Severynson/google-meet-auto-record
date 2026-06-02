import Cocoa

final class StatusBarController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var windowController: StatusWindowController?

    init() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "MeetRecorder")
            button.image?.isTemplate = true
            button.action = #selector(toggleWindow)
            button.target = self
        }
    }

    @objc private func toggleWindow() {
        if let wc = windowController, wc.window?.isVisible == true {
            wc.close()
        } else {
            showStatusWindow()
        }
    }

    func showStatusWindow() {
        if windowController == nil {
            windowController = StatusWindowController()
        }
        windowController?.showWindow(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
