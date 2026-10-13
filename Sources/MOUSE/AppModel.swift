import AppKit
import Combine
import ScrollCore
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var isRunning = false
    @Published private(set) var launchAtLogin = false
    @Published private(set) var loginNeedsApproval = false
    @Published private(set) var serviceFailed = false
    @Published var loginError: String?
    @Published var showCompatibility = false

    private let service = ScrollService()
    private var timer: Timer?
    private var lastAttempt = Date.distantPast
    private let defaults = UserDefaults.standard

    init() {
        defaults.register(defaults: ["reverseMouseScrolling": true])
        isEnabled = defaults.bool(forKey: "reverseMouseScrolling")
        refresh(forceRetry: true)
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer?.tolerance = 0.5
    }

    var statusText: String {
        if !isEnabled { return "已暂停" }
        if !accessibilityGranted { return "等待授权" }
        if isRunning { return "正在运行" }
        return "连接待恢复"
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: "reverseMouseScrolling")
        refresh(forceRetry: true)
    }

    func refresh(forceRetry: Bool = false) {
        accessibilityGranted = ScrollService.permissions.accessibilityGranted
        if !isEnabled || !accessibilityGranted {
            service.stop()
            serviceFailed = false
        } else if !service.isRunning && (forceRetry || Date().timeIntervalSince(lastAttempt) > 10) {
            lastAttempt = Date()
            switch service.start() {
            case .started:
                serviceFailed = false
            case .accessibilityRequired:
                accessibilityGranted = false
                serviceFailed = false
            case .eventTapUnavailable:
                serviceFailed = true
            }
        }
        isRunning = service.isRunning
        refreshLoginStatus()
    }

    func requestPermission() {
        ScrollService.requestAccessibilityPermission()
        openAccessibilitySettings()
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    func restartService() {
        service.stop()
        refresh(forceRetry: true)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        loginError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginError = "无法更新登录项：\(error.localizedDescription)"
        }
        refreshLoginStatus()
    }

    func openLoginSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func refreshLoginStatus() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled || status == .requiresApproval
        loginNeedsApproval = status == .requiresApproval
    }

    func shutdown() {
        timer?.invalidate()
        timer = nil
        service.stop()
    }
}
