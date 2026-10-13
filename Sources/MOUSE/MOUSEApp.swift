import AppKit
import Combine
import SwiftUI

@main
enum MOUSEApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var window: NSWindow?
    private var observation: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let identifier = Bundle.main.bundleIdentifier,
           let existing = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            existing.activate(options: [.activateIgnoringOtherApps])
            NSApp.terminate(nil)
            return
        }

        model = AppModel()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "arrow.up.arrow.down", accessibilityDescription: "MOUSE 滚动方向")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        popover.behavior = .transient
        let popoverController = NSHostingController(rootView: PanelView(model: model))
        popoverController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = popoverController

        observation = model.$isRunning.combineLatest(model.$isEnabled).sink { [weak self] running, enabled in
            self?.statusItem.button?.appearsDisabled = !running
            self?.statusItem.button?.toolTip = enabled ? (running ? "MOUSE · 鼠标反向滚动已开启" : "MOUSE · 等待系统权限") : "MOUSE · 已暂停"
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didActivate), name: NSApplication.didBecomeActiveNotification, object: nil)

        if !UserDefaults.standard.bool(forKey: "hasOpenedMOUSE") || !model.accessibilityGranted {
            showWindow()
            UserDefaults.standard.set(true, forKey: "hasOpenedMOUSE")
        }
    }

    @objc private func togglePopover() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            let enabledItem = NSMenuItem(title: "鼠标反向滚动", action: #selector(toggleEnabled), keyEquivalent: "")
            enabledItem.target = self
            enabledItem.state = model.isEnabled ? .on : .off
            menu.addItem(enabledItem)
            let openItem = NSMenuItem(title: "打开 MOUSE…", action: #selector(showWindow), keyEquivalent: "")
            openItem.target = self
            menu.addItem(openItem)
            menu.addItem(.separator())
            menu.addItem(withTitle: "退出 MOUSE", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
            return
        }
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil); return }
        if window?.isVisible == true {
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        model.refresh(forceRetry: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleEnabled() { model.setEnabled(!model.isEnabled) }

    @objc private func showWindow() {
        popover.performClose(nil)
        if window == nil {
            let controller = NSHostingController(rootView: PanelView(model: model).padding(.top, 18))
            controller.sizingOptions = [.minSize, .maxSize, .preferredContentSize]
            let window = NSWindow(contentViewController: controller)
            window.title = "MOUSE"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func didWake() { model?.restartService() }
    @objc private func didActivate() { model?.refresh(forceRetry: true) }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if model != nil { showWindow() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        observation?.cancel()
        model?.shutdown()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }
}
