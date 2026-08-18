@preconcurrency import AppKit
import CodexPaceBarAppSupport
import CodexActivityInsightsControlAdapter
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let settings: SettingsStore
    private let launchAtLogin: LaunchAtLoginController
    private let activityInsights: ActivityInsightsCollectorController
    private var window: NSWindow?

    init(
        settings: SettingsStore,
        launchAtLogin: LaunchAtLoginController,
        activityInsights: ActivityInsightsCollectorController = .init()
    ) {
        self.settings = settings
        self.launchAtLogin = launchAtLogin
        self.activityInsights = activityInsights
    }

    func show() {
        launchAtLogin.refresh()
        activityInsights.refresh()

        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(
            rootView: SettingsView(
                settings: settings,
                launchAtLogin: launchAtLogin,
                activityInsights: activityInsights
            )
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 620, height: 760))
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
