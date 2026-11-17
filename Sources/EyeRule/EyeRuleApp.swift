import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let timer = EyeTimer()

    func applicationWillTerminate(_ notification: Notification) {
        timer.shutdown()
    }
}

struct MenuLabel: View {
    @ObservedObject var timer: EyeTimer
    var body: some View {
        Image(systemName: timer.phase == .resting ? "eye.fill" : "eye")
        if timer.cameraActive {
            Image(systemName: "camera.fill")
        }
        if !timer.mode.usesCard { Text(timer.label) }
    }
}

@main
struct EyeRuleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    /// The menu bar icon is only needed on Macs without a notch, where the pill is hidden.
    private var showMenuBarIcon: Bool {
        (NSScreen.main?.safeAreaInsets.top ?? 0) == 0
    }

    var body: some Scene {
        MenuBarExtra(isInserted: .constant(showMenuBarIcon)) {
            ContentView(timer: delegate.timer)
        } label: {
            MenuLabel(timer: delegate.timer)
        }
        .menuBarExtraStyle(.window)

        Settings { EmptyView() }
    }
}
