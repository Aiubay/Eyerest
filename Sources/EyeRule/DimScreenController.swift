import AppKit
import SwiftUI

struct DimScreenPolicy {
    static func allowsPresentation(enabled: Bool, resting: Bool, running: Bool,
                                   locked: Bool, sleeping: Bool, busy: Bool,
                                   fullscreen: Bool?) -> Bool {
        enabled && resting && running && !locked && !sleeping && !busy && fullscreen == false
    }

    static func coversScreen(_ window: CGRect, screen: CGRect) -> Bool {
        window.contains(screen.insetBy(dx: 2, dy: 2))
    }
}

@MainActor
private final class DimPanel: NSPanel {
    var dismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { dismiss?() }
        else { super.keyDown(with: event) }
    }

    override func cancelOperation(_ sender: Any?) {
        dismiss?()
    }
}

@MainActor
final class DimScreenController: NSObject, NSWindowDelegate {
    private var panel: DimPanel?
    private var lastExternalApp: NSRunningApplication?
    private var sourceApp: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?

    var isVisible: Bool { panel != nil }

    override init() {
        super.init()
        rememberExternal(NSWorkspace.shared.frontmostApplication)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self,
                      let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
                self.rememberExternal(app)
                self.hide()
            }
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    private func rememberExternal(_ app: NSRunningApplication?) {
        if let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
           app.activationPolicy == .regular {
            lastExternalApp = app
        }
    }

    private func fullscreenStatus(for app: NSRunningApplication) -> Bool? {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }
        let screen = CGDisplayBounds(CGMainDisplayID())
        var foundWindow = false
        for window in windows {
            guard window[kCGWindowOwnerPID as String] as? pid_t == app.processIdentifier,
                  window[kCGWindowLayer as String] as? Int == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { continue }
            foundWindow = true
            if DimScreenPolicy.coversScreen(frame, screen: screen) { return true }
        }
        return foundWindow ? false : nil
    }

    func show(timer: EyeTimer, busy: Bool, locked: Bool, sleeping: Bool) {
        guard panel == nil, let screen = NSScreen.screens.first else { return }
        rememberExternal(NSWorkspace.shared.frontmostApplication)
        guard let app = lastExternalApp, !app.isTerminated,
              DimScreenPolicy.allowsPresentation(
                enabled: timer.dimScreenDuringBreaks, resting: timer.phase == .resting,
                running: timer.isRunning, locked: locked, sleeping: sleeping,
                busy: busy, fullscreen: fullscreenStatus(for: app)
              ) else { return }

        let panel = DimPanel(contentRect: screen.frame,
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.dismiss = { [weak self] in self?.hide() }
        panel.contentView = NSHostingView(rootView: DimBreakView(timer: timer) { [weak self] in
            self?.hide()
        })
        self.panel = panel
        sourceApp = app
        panel.makeKeyAndOrderFront(nil)
    }

    func checkInterruption(cameraActive: Bool) {
        guard panel != nil, let sourceApp else { return }
        if MeetingDetector.micInUse() || (!cameraActive && MeetingDetector.cameraInUse())
            || fullscreenStatus(for: sourceApp) != false {
            hide()
        }
    }

    func hide() {
        guard let panel else { return }
        self.panel = nil
        sourceApp = nil
        panel.delegate = nil
        panel.orderOut(nil)
        panel.close()
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    func shutdown() {
        hide()
        if let observer = activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        activationObserver = nil
        screenObserver = nil
    }
}

private struct DimBreakView: View {
    @ObservedObject var timer: EyeTimer
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
            VStack(spacing: 20) {
                RingView(progress: timer.progress, text: "\(timer.remaining)", size: 116, color: .green)
                Text("Look 20 feet away")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                Text(timer.prompt)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                if timer.cameraActive {
                    Label("Blinks \(timer.blinks)/10", systemImage: "camera.fill")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.green)
                }
                HStack(spacing: 12) {
                    Button("Skip") { timer.skipBreak() }
                    Button("5 more min") { timer.snooze() }
                }
                .buttonStyle(PillButtonStyle())
                Button("Dismiss dimming · Esc", action: dismiss)
                    .buttonStyle(PillButtonStyle(prominent: true))
                    .keyboardShortcut(.cancelAction)
                Text("Dismissing keeps your break running.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .foregroundStyle(.white)
            .padding(36)
            .background(RoundedRectangle(cornerRadius: 28).fill(Color.black.opacity(0.85)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .dark)
    }
}
