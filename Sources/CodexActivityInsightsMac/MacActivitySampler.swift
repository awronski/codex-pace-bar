@preconcurrency import AppKit
import CodexActivityInsightsCore
import CoreGraphics
import Foundation

@MainActor
public final class MacActivitySampler: NSObject {
    public static let codexDesktopBundleIdentifier = "com.openai.codex"

    private let notificationCenter: NotificationCenter
    private let idleReader: @MainActor @Sendable () -> TimeInterval
    private let frontmostBundleIdentifierReader: @MainActor @Sendable () -> String?
    private var started = false
    private var systemAwake = true
    private var screenAwake = true
    private var sessionActive = true

    public init(
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        idleReader: @escaping @MainActor @Sendable () -> TimeInterval = {
            let anyInput = CGEventType(rawValue: UInt32.max)!
            return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput)
        },
        frontmostBundleIdentifierReader: @escaping @MainActor @Sendable () -> String? = {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        }
    ) {
        self.notificationCenter = notificationCenter
        self.idleReader = idleReader
        self.frontmostBundleIdentifierReader = frontmostBundleIdentifierReader
    }

    public func start() {
        guard !started else { return }
        started = true
        notificationCenter.addObserver(
            self,
            selector: #selector(willSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(screenDidSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(screenDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(sessionDidResignActive),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(sessionDidBecomeActive),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
    }

    public func stop() {
        guard started else { return }
        notificationCenter.removeObserver(self)
        started = false
    }

    public func observation(at date: Date, intervalSeconds: TimeInterval) -> ActivityObservation {
        guard systemAwake, screenAwake, sessionActive else {
            return ActivityObservation(
                timestamp: date,
                intervalSeconds: intervalSeconds,
                idleSeconds: nil,
                codexFocus: .unknown
            )
        }
        let idle = idleReader()
        let codexFocus: ActivityCodexFocusState
        if let bundleIdentifier = frontmostBundleIdentifierReader() {
            codexFocus = bundleIdentifier == Self.codexDesktopBundleIdentifier
                ? .focused
                : .notFocused
        } else {
            codexFocus = .unknown
        }
        return ActivityObservation(
            timestamp: date,
            intervalSeconds: intervalSeconds,
            idleSeconds: idle.isFinite && idle >= 0 ? idle : nil,
            codexFocus: codexFocus
        )
    }

    @objc private func willSleep(_ notification: Notification) { systemAwake = false }

    @objc private func didWake(_ notification: Notification) { systemAwake = true }

    @objc private func screenDidSleep(_ notification: Notification) { screenAwake = false }

    @objc private func screenDidWake(_ notification: Notification) { screenAwake = true }

    @objc private func sessionDidResignActive(_ notification: Notification) { sessionActive = false }

    @objc private func sessionDidBecomeActive(_ notification: Notification) { sessionActive = true }
}
