import AppKit
import SwiftUI
import ServiceManagement
import UserNotifications

enum NotifyMode: String, CaseIterable, Identifiable {
    case card, native, both
    var id: String { rawValue }
    var title: String {
        switch self {
        case .card: return "Corner card"
        case .native: return "macOS notification"
        case .both: return "Both"
        }
    }
    var shortTitle: String {
        switch self {
        case .card: return "Pill"
        case .native: return "Alert"
        case .both: return "Both"
        }
    }
    var usesCard: Bool { self != .native }
    var usesNative: Bool { self != .card }
}

enum SoundTheme: String, CaseIterable, Identifiable {
    case chime, water, soft, silent
    var id: String { rawValue }
    var title: String {
        switch self {
        case .chime: return "Chime"
        case .water: return "Water drop"
        case .soft: return "Soft"
        case .silent: return "Silent"
        }
    }
    var startSound: String? {
        switch self {
        case .chime: return "Glass"
        case .water: return "Bottle"
        case .soft: return "Ping"
        case .silent: return nil
        }
    }
    var endSound: String? {
        switch self {
        case .chime: return "Tink"
        case .water: return "Pop"
        case .soft: return "Purr"
        case .silent: return nil
        }
    }
}

@MainActor
final class EyeTimer: ObservableObject {
    enum Phase { case working, resting }

    static let snoozeSeconds = 5 * 60
    static let idleThreshold: Double = 60
    static let awayResetThreshold: Double = 300

    static let prompts = [
        "Look at the farthest thing you can see.",
        "Blink slowly 10 times.",
        "Roll your shoulders back.",
        "Look out a window if you can.",
        "Close your eyes and breathe out.",
        "Relax your jaw and unclench your teeth.",
        "Look left, then right, slowly.",
    ]

    // MARK: State

    @Published var phase: Phase = .working
    @Published var remaining: Int
    @Published var isRunning = true
    @Published var autoPaused = false
    @Published var deferred = false
    @Published var showDone = false
    @Published var cardExpanded = false
    @Published var showControls = false
    @Published var blinks = 0
    @Published var prompt = EyeTimer.prompts[0]
    @Published var history: [String: Int]
    @Published var launchNote: String?
    /// Measured panel height per controls tab.
    var tabHeights: [ControlsTab: CGFloat] = [:]
    @Published var controlsHeight: CGFloat = ControlsTab.timer.height

    // MARK: Persisted settings

    @Published var mode: NotifyMode {
        didSet {
            defaults.set(mode.rawValue, forKey: "notifyMode")
            card.sync(timer: self)
        }
    }
    @Published var soundTheme: SoundTheme {
        didSet { defaults.set(soundTheme.rawValue, forKey: "soundTheme") }
    }
    @Published var workMinutes: Int {
        didSet {
            defaults.set(workMinutes, forKey: "workMinutes")
            if phase == .working && !deferred { remaining = workSeconds }
        }
    }
    @Published var breakSeconds: Int {
        didSet { defaults.set(breakSeconds, forKey: "breakSeconds") }
    }
    @Published var dailyGoal: Int {
        didSet { defaults.set(dailyGoal, forKey: "dailyGoal") }
    }
    @Published var insights: BreakInsights
    @Published var dimScreenDuringBreaks: Bool {
        didSet {
            defaults.set(dimScreenDuringBreaks, forKey: "dimScreenDuringBreaks")
            if !dimScreenDuringBreaks { dimScreen.hide() }
        }
    }
    @Published var smartPause: Bool {
        didSet {
            defaults.set(smartPause, forKey: "smartPause")
            if !smartPause {
                autoPaused = false
                presenceResult = nil
                cancelPresenceCheck()
            }
        }
    }
    @Published var meetingMode: Bool {
        didSet { defaults.set(meetingMode, forKey: "meetingMode") }
    }
    @Published var cameraEnabled: Bool {
        didSet {
            guard cameraEnabled != oldValue else { return }
            defaults.set(cameraEnabled, forKey: "cameraEnabled")
            if cameraEnabled {
                camera.prepare { [weak self] granted in
                    guard let self else { return }
                    if granted {
                        self.cameraStatus = "Camera ready. Blinks count during breaks."
                    } else {
                        self.cameraEnabled = false
                        self.cameraStatus = "Camera access denied. Turn it on in System Settings."
                    }
                }
            } else {
                stopCamera()
                presenceResult = nil
                cameraStatus = nil
            }
        }
    }
    @Published var cameraStatus: String?
    @Published var cameraActive = false
    @Published var cameraPresencePause: Bool {
        didSet {
            defaults.set(cameraPresencePause, forKey: "cameraPresencePause")
            if !cameraPresencePause {
                presenceResult = nil
                cancelPresenceCheck()
            }
        }
    }
    @Published var blinkReminderEnabled: Bool {
        didSet { defaults.set(blinkReminderEnabled, forKey: "blinkReminderEnabled") }
    }
    @Published var blinkRateThreshold: Int {
        didSet { defaults.set(blinkRateThreshold, forKey: "blinkRateThreshold") }
    }
    /// Hides the resting island while a fullscreen app is in front. Breaks still appear.
    @Published var hideInFullscreen: Bool {
        didSet {
            defaults.set(hideInFullscreen, forKey: "hideInFullscreen")
            refreshFullscreen()
        }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            guard !suppressLaunch, oldValue != launchAtLogin else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
                launchNote = nil
            } catch {
                suppressLaunch = true
                launchAtLogin = oldValue
                suppressLaunch = false
                launchNote = "Couldn't change this. Try moving the app to Applications."
            }
        }
    }

    private let defaults = UserDefaults.standard
    private var suppressLaunch = false
    private var ticker: Timer?
    private var deferredTicks = 0
    private var lockedSince: Date?
    private var promptIndex = 0
    private var currentSound: NSSound?
    private let card = BreakCardController()
    private let camera = CameraTracker()
    private let dimScreen = DimScreenController()
    private var sleeping = false
    private var workspaceObservers: [NSObjectProtocol] = []

    private enum CameraUse { case none, breakBlinks, blinkRate, presence }
    private var cameraUse: CameraUse = .none
    private var presenceResult: (present: Bool, at: Date)?
    private var presenceCheckStarted: Date?
    private var rateSampleStarted: Date?
    private var nextRateSample = Date().addingTimeInterval(60)
    private var lastRateAlert: Date?

    private static let presenceSeconds: TimeInterval = 3
    private static let rateSampleSeconds: TimeInterval = 15

    var workSeconds: Int { workMinutes * 60 }

    // MARK: Init

    init() {
        let d = UserDefaults.standard
        let work = d.object(forKey: "workMinutes") as? Int ?? 20
        workMinutes = work
        breakSeconds = d.object(forKey: "breakSeconds") as? Int ?? 20
        dailyGoal = d.object(forKey: "dailyGoal") as? Int ?? 15
        smartPause = d.object(forKey: "smartPause") as? Bool ?? true
        hideInFullscreen = d.object(forKey: "hideInFullscreen") as? Bool ?? true
        meetingMode = d.object(forKey: "meetingMode") as? Bool ?? true
        cameraEnabled = d.object(forKey: "cameraEnabled") as? Bool ?? false
        cameraPresencePause = d.object(forKey: "cameraPresencePause") as? Bool ?? true
        blinkReminderEnabled = d.object(forKey: "blinkReminderEnabled") as? Bool ?? false
        blinkRateThreshold = d.object(forKey: "blinkRateThreshold") as? Int ?? 10
        soundTheme = SoundTheme(rawValue: d.string(forKey: "soundTheme") ?? "") ?? .chime
        mode = NotifyMode(rawValue: d.string(forKey: "notifyMode") ?? "") ?? .card
        history = d.dictionary(forKey: "history") as? [String: Int] ?? [:]
        insights = d.data(forKey: "breakInsights").flatMap {
            try? JSONDecoder().decode(BreakInsights.self, from: $0)
        } ?? BreakInsights()
        dimScreenDuringBreaks = d.bool(forKey: "dimScreenDuringBreaks")
        launchAtLogin = SMAppService.mainApp.status == .enabled
        remaining = work * 60

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }

        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.lockedSince = Date()
                self?.dimScreen.hide()
                self?.stopCamera()
                self?.persistInsights()
            }
        }
        center.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didUnlock() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sleeping = true
                self?.dimScreen.hide()
                self?.stopCamera()
                self?.persistInsights()
            }
        })
        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.sleeping = false }
        })
        // Entering or leaving fullscreen switches Space; switching apps can bring one forward.
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleFullscreenCheck() }
            })
        }
        persistInsights()
        card.sync(timer: self)
        refreshFullscreen()

        camera.onBlink = { [weak self] in self?.countBlink() }
        camera.onActive = { [weak self] active in self?.cameraActive = active }
        camera.onStatus = { [weak self] text in self?.cameraStatus = text }
    }

    // MARK: Derived values

    var isActive: Bool { isRunning && !autoPaused }

    var label: String {
        String(format: "%d:%02d", remaining / 60, remaining % 60)
    }

    var compactLabel: String {
        // The resting wings are narrow; a call shows as an icon on the other side.
        if isUrgent && !deferred { return "\(remaining)s" }
        return label
    }

    var progress: Double {
        let total = phase == .working ? workSeconds : breakSeconds
        return 1 - Double(remaining) / Double(max(total, 1))
    }

    /// Cyan by day, lavender in the evening, periwinkle at night. Yellow, orange and green override it.
    var accent: Color {
        if phase == .resting { return .green }
        if remaining <= 60 { return .orange }
        if remaining <= 300 { return .yellow }
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<17: return .cyan
        case 17..<21: return Color(red: 0.78, green: 0.62, blue: 1.0)
        default: return Color(red: 0.55, green: 0.6, blue: 1.0)
        }
    }

    var isUrgent: Bool { phase == .working && isActive && !deferred && remaining <= 60 }

    var message: String {
        if !isRunning { return "Paused. I'll wait for you." }
        if autoPaused { return "You stepped away. I'll resume when you're back." }
        if deferred { return "You're in a call. I'll wait until it's over." }
        switch phase {
        case .working:
            let m = (remaining + 59) / 60
            return "You've got \(m) minute\(m == 1 ? "" : "s"). I'll nudge you."
        case .resting:
            return "Look at something far away."
        }
    }

    // MARK: Stats

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private func key(_ date: Date) -> String { Self.dayFormatter.string(from: date) }

    var breaksToday: Int { history[key(Date())] ?? 0 }

    var streak: Int {
        let cal = Calendar.current
        var day = Date()
        if (history[key(day)] ?? 0) == 0 {
            guard let y = cal.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = y
        }
        var n = 0
        while (history[key(day)] ?? 0) > 0 {
            n += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return n
    }

    struct DayStat: Identifiable {
        let id: Int
        let label: String
        let count: Int
        let isToday: Bool
    }

    var lastSevenDays: [DayStat] {
        let cal = Calendar.current
        let f = DateFormatter()
        f.dateFormat = "EEEEE"
        return (0..<7).reversed().map { offset in
            let date = cal.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
            return DayStat(id: offset, label: f.string(from: date),
                           count: history[key(date)] ?? 0, isToday: offset == 0)
        }
    }

    var weeklyInsights: BreakInsights.Week {
        insights.week(ending: Date(), history: history)
    }

    var weeklyComparison: String {
        let now = Date()
        let current = insights.week(ending: now, history: history).completed
        let previous = insights.previousWeek(ending: now, history: history).completed
        if previous == 0 { return "No completed breaks in the preceding 7 days." }
        let difference = current - previous
        if difference == 0 { return "Same number of completions as the preceding 7 days." }
        return "\(abs(difference)) \(difference > 0 ? "more" : "fewer") completed than the preceding 7 days."
    }

    private func recordBreak() {
        history[key(Date()), default: 0] += 1
        defaults.set(history, forKey: "history")
    }

    private func persistInsights() {
        if let data = try? JSONEncoder().encode(insights) {
            defaults.set(data, forKey: "breakInsights")
        }
    }

    private func endTrackedBreak(_ outcome: BreakInsights.Outcome) {
        insights.endBreak(outcome, on: Date())
        persistInsights()
        dimScreen.hide()
    }

    func shutdown() {
        endTrackedBreak(.stopped)
        dimScreen.shutdown()
        stopCamera()
        ticker?.invalidate()
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
    }

    // MARK: Actions

    func toggle() {
        isRunning.toggle()
        if !isRunning { dimScreen.hide(); persistInsights() }
    }

    func openControls() {
        controlsHeight = height(for: .timer)
        card.openControls(timer: self)
    }

    /// Tallest panel any tab needs, so the window can be reserved once.
    var tallestControls: CGFloat {
        ControlsTab.allCases.map { height(for: $0) }.max() ?? ControlsTab.settings.height
    }

    /// Called when a tab's measured height exceeds what the window has reserved.
    func reserveControls() { card.reserveControls(timer: self) }

    /// Panel height for a tab: measured once rendered, otherwise a first guess.
    func height(for tab: ControlsTab) -> CGFloat { tabHeights[tab] ?? tab.height }

    private var fullscreenCheck: Task<Void, Never>?

    /// Checks now and again once the Space animation has settled, when window frames are final.
    private func scheduleFullscreenCheck() {
        refreshFullscreen()
        fullscreenCheck?.cancel()
        fullscreenCheck = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            self?.refreshFullscreen()
        }
    }

    func refreshFullscreen() {
        var fullscreen = false
        if hideInFullscreen, let app = NSWorkspace.shared.frontmostApplication,
           app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            fullscreen = DimScreenPolicy.fullscreenStatus(for: app) == true
        }
        card.setHiddenForFullscreen(fullscreen, timer: self)
    }

    func closeControls() { card.hide(timer: self) }

    func reset() {
        endTrackedBreak(.skipped)
        card.hide(timer: self)
        stopCamera()
        phase = .working
        remaining = workSeconds
        showDone = false
        deferred = false
        isRunning = true
    }

    func startBreakNow() { startRest(native: false) }

    func skipBreak() {
        endTrackedBreak(.skipped)
        card.hide(timer: self)
        stopCamera()
        phase = .working
        remaining = workSeconds
        showDone = false
    }

    func snooze() {
        endTrackedBreak(.postponed)
        card.hide(timer: self)
        stopCamera()
        phase = .working
        remaining = Self.snoozeSeconds
        showDone = false
        deferred = false
    }

    func blink() {
        countBlink()
    }

    private func countBlink() {
        guard phase == .resting, !showDone else { return }
        blinks += 1
        if blinks == 10 { haptic() }
    }

    func previewSound() { play(soundTheme.startSound) }

    // MARK: Cycle

    private func startRest(native: Bool) {
        guard phase != .resting else { return }
        let dimmingBusy = dimScreenDuringBreaks && (cameraActive || cameraUse != .none || MeetingDetector.busy)
        insights.beginBreak()
        phase = .resting
        remaining = breakSeconds
        showDone = false
        isRunning = true
        deferred = false
        showControls = false
        blinks = 0
        presenceResult = nil
        presenceCheckStarted = nil
        rateSampleStarted = nil
        if cameraEnabled && mode.usesCard {
            if MeetingDetector.busy && !cameraActive {
                cameraStatus = "Camera skipped: another app is using it."
            } else {
                cameraUse = .breakBlinks
                camera.start()
            }
        }
        prompt = Self.prompts[promptIndex % Self.prompts.count]
        promptIndex += 1
        if mode.usesCard {
            card.show(timer: self)
            play(soundTheme.startSound)
            haptic()
        }
        if native && mode.usesNative {
            notify("Look away", "Focus on something 20 feet away for \(breakSeconds) seconds.")
        }
        dimScreen.show(timer: self, busy: dimmingBusy, locked: lockedSince != nil, sleeping: sleeping)
    }

    private func finishRest() {
        endTrackedBreak(.completed)
        stopCamera()
        recordBreak()
        phase = .working
        remaining = workSeconds
        if mode.usesCard {
            showDone = true
            card.hide(after: 3, timer: self)
            play(soundTheme.endSound)
        }
        if mode.usesNative {
            notify("Nice, eyes rested", "Next break in \(workMinutes) minutes.")
        }
    }

    private func tick() {
        dimScreen.checkInterruption(cameraActive: cameraActive || cameraUse == .breakBlinks)
        guard isRunning, !sleeping else { return }
        if phase == .resting && lockedSince != nil { return }

        let held = phase == .working ? updateAutoPause() : false
        tickCamera()
        if held { return }

        if phase == .working && deferred {
            deferredTicks += 1
            if deferredTicks % 5 == 0 && !MeetingDetector.busy { startRest(native: true) }
            return
        }

        insights.advance(on: Date(), running: phase == .resting)
        remaining -= 1
        guard remaining <= 0 else { return }
        switch phase {
        case .working:
            if meetingMode && MeetingDetector.busy {
                deferred = true
                deferredTicks = 0
                remaining = 0
            } else {
                startRest(native: true)
            }
        case .resting:
            finishRest()
        }
    }

    /// Returns true when the countdown should hold because you're away.
    private func updateAutoPause() -> Bool {
        guard smartPause else {
            autoPaused = false
            presenceResult = nil
            cancelPresenceCheck()
            return false
        }

        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                           eventType: CGEventType(rawValue: ~0)!)
        let away = lockedSince != nil || idle >= Self.idleThreshold

        if !away {
            autoPaused = false
            presenceResult = nil
            cancelPresenceCheck()
            return false
        }

        if lockedSince != nil {
            autoPaused = true
            if idle >= Self.awayResetThreshold { remaining = workSeconds }
            return true
        }

        if cameraEnabled && cameraPresencePause {
            if cameraUse == .blinkRate {
                autoPaused = false
                return false
            }
            if let result = presenceResult {
                if !result.present {
                    autoPaused = true
                    if idle >= Self.awayResetThreshold { remaining = workSeconds }
                    return true
                }
                if Date().timeIntervalSince(result.at) < 45 {
                    autoPaused = false
                    return false
                }
            }
            if cameraUse == .none && !MeetingDetector.busy {
                beginPresenceCheck()
            }
            autoPaused = false
            return false
        }

        autoPaused = true
        if idle >= Self.awayResetThreshold { remaining = workSeconds }
        return true
    }

    private func beginPresenceCheck() {
        guard cameraUse == .none else { return }
        cameraUse = .presence
        presenceCheckStarted = Date()
        camera.start()
    }

    private func cancelPresenceCheck() {
        guard cameraUse == .presence else { return }
        cameraUse = .none
        presenceCheckStarted = nil
        camera.stop()
    }

    private func stopCamera() {
        if cameraUse == .blinkRate {
            nextRateSample = Date().addingTimeInterval(120)
        }
        cameraUse = .none
        rateSampleStarted = nil
        presenceCheckStarted = nil
        camera.stop()
    }

    /// Finishes running samples and starts a blink-rate sample when one is due.
    private func tickCamera() {
        let now = Date()

        if cameraUse == .blinkRate, let started = rateSampleStarted,
           now.timeIntervalSince(started) >= Self.rateSampleSeconds {
            cameraUse = .none
            rateSampleStarted = nil
            nextRateSample = now.addingTimeInterval(120)
            camera.stop { [weak self] sample in
                self?.evaluateRateSample(sample)
            }
            return
        }

        if cameraUse == .presence, let started = presenceCheckStarted,
           now.timeIntervalSince(started) >= Self.presenceSeconds {
            cameraUse = .none
            presenceCheckStarted = nil
            camera.stop { [weak self] sample in
                guard let self, sample.frames > 0 else { return }
                let present = Double(sample.faceFrames) / Double(sample.frames) > 0.3
                self.presenceResult = (present, Date())
                if present { self.autoPaused = false }
            }
            return
        }

        guard phase == .working, blinkReminderEnabled, cameraEnabled,
              isActive, !deferred, cameraUse == .none else { return }
        guard !MeetingDetector.busy, now >= nextRateSample else { return }

        cameraUse = .blinkRate
        rateSampleStarted = now
        nextRateSample = now.addingTimeInterval(120)
        camera.start()
    }

    private func evaluateRateSample(_ sample: CameraTracker.Sample) {
        guard sample.frames > 0 else { return }
        let faceRatio = Double(sample.faceFrames) / Double(sample.frames)
        guard faceRatio >= 0.5 else { return }
        let perMinute = Double(sample.blinks) / Self.rateSampleSeconds * 60
        guard perMinute < Double(blinkRateThreshold) else { return }
        if let last = lastRateAlert, Date().timeIntervalSince(last) < 600 { return }
        lastRateAlert = Date()
        notify("Blink more",
               "About \(Int(perMinute.rounded())) blinks a minute. Try a few slow, full blinks.")
    }

    private func didUnlock() {
        presenceResult = nil
        if let since = lockedSince, Date().timeIntervalSince(since) >= Self.awayResetThreshold,
           phase == .working, !deferred {
            remaining = workSeconds
        }
        lockedSince = nil
    }

    // MARK: Feedback

    private func play(_ name: String?) {
        guard let name, let sound = NSSound(named: name) else { return }
        currentSound?.stop()
        currentSound = sound
        sound.play()
    }

    private func haptic() {
        guard soundTheme != .silent else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    private func notify(_ title: String, _ body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = (mode == .native && soundTheme != .silent) ? .default : nil
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

@MainActor
final class BreakCardController {
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?
    private var monitor: Any?
    private var hasNotch = false
    private var floating: Bool { !hasNotch }
    /// A fullscreen app is in front: the resting island steps away, a break still shows.
    private var hiddenForFullscreen = false
    private var topInset: CGFloat = 24
    private var restingHeight: CGFloat = 24
    private var notchWidth: CGFloat = 140
    private var screenFrame: NSRect = .zero

    static let wing: CGFloat = 92
    /// Side room of the compact pill, either side of the notch.
    static let compactWing: CGFloat = 44
    /// Extra transparent room so the spring animation can overshoot without clipping.
    static let overshoot: CGFloat = 24
    static let width: CGFloat = 340
    static let contentHeight: CGFloat = 165
    /// Floating island (Macs without a notch).
    /// Outward curve at the top corners of a notch island.
    static let flare: CGFloat = 9
    /// How much the compact island grows under the pointer.
    static let hoverGrowWidth: CGFloat = 16
    static let hoverGrowHeight: CGFloat = 4
    static let floatingGap: CGFloat = 8
    static let floatingHeight: CGFloat = 34
    static let floatingCompactWidth: CGFloat = 200
    static let floatingHeadroom: CGFloat = 6

    func sync(timer: EyeTimer) {
        if timer.mode.usesCard {
            ensurePanel(timer: timer)
            if hiddenForFullscreen && !timer.cardExpanded { panel?.orderOut(nil) }
            else { panel?.orderFrontRegardless() }
        } else {
            hideTask?.cancel()
            timer.cardExpanded = false
            timer.showControls = false
            removeMonitor()
            panel?.orderOut(nil)
            panel = nil
        }
    }

    /// Width of the expanded card. The compact pill is narrower.
    private var pillWidth: CGFloat { max(notchWidth + Self.wing * 2, Self.width) }
    private var compactWidth: CGFloat { notchWidth + Self.compactWing * 2 + Self.flare * 2 }

    private func frame(expanded: Bool, controlsHeight: CGFloat? = nil) -> NSRect {
        let gap = floating ? Self.floatingGap : 0
        let headroom = floating ? Self.floatingHeadroom : topInset
        let compactW = floating ? Self.floatingCompactWidth : compactWidth
        let w = expanded ? pillWidth + Self.overshoot * 2 : compactW + Self.hoverGrowWidth
        let h = gap + (expanded ? headroom + (controlsHeight ?? Self.contentHeight) + Self.overshoot
                       : restingHeight + Self.hoverGrowHeight)
        return NSRect(x: screenFrame.midX - w / 2, y: screenFrame.maxY - h, width: w, height: h)
    }

    private func ensurePanel(timer: EyeTimer) {
        guard panel == nil, let screen = NSScreen.main else { return }
        hasNotch = screen.safeAreaInsets.top > 0
        // Cover the whole menu bar, including any strip below the notch.
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        topInset = max(screen.safeAreaInsets.top, menuBar, 24) + 1
        screenFrame = screen.frame
        if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            notchWidth = screen.frame.width - l.width - r.width
        }
        if notchWidth <= 0 { notchWidth = 140 }
        if floating { topInset = Self.floatingHeight }
        // Rest at the camera's height, like Vorssaint; open below the whole menu bar.
        restingHeight = floating ? topInset : max(screen.safeAreaInsets.top, 24)

        let host = NSHostingView(rootView: BreakCardView(timer: timer, topInset: topInset, restingHeight: restingHeight,
                                                         notchWidth: notchWidth,
                                                         pillWidth: pillWidth,
                                                         compactWidth: compactWidth,
                                                         floating: floating))
        let p = NSPanel(contentRect: frame(expanded: false),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.contentView = host
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel = p
    }

    private func expand(timer: EyeTimer) {
        hideTask?.cancel()
        ensurePanel(timer: timer)
        // Reserve room for the tallest tab up front. Tab changes then only animate the
        // shape inside the window; resizing the window mid-animation made it jump.
        panel?.setFrame(frame(expanded: true, controlsHeight: timer.showControls ? timer.tallestControls : nil), display: true)
        panel?.orderFrontRegardless()
        timer.cardExpanded = true
    }

    func show(timer: EyeTimer) {
        timer.showControls = false
        expand(timer: timer)
    }

    func openControls(timer: EyeTimer) {
        timer.showControls = true
        expand(timer: timer)
        removeMonitor()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak timer] _ in
            Task { @MainActor in
                guard let self, let timer, timer.showControls else { return }
                self.hide(timer: timer)
            }
        }
    }

    func setHiddenForFullscreen(_ hidden: Bool, timer: EyeTimer) {
        guard hidden != hiddenForFullscreen else { return }
        hiddenForFullscreen = hidden
        guard timer.mode.usesCard else { return }
        // An open break card or open controls stay; the island hides when they close.
        if hidden {
            if !timer.cardExpanded { panel?.orderOut(nil) }
        } else {
            ensurePanel(timer: timer)
            panel?.orderFrontRegardless()
        }
    }

    func reserveControls(timer: EyeTimer) {
        guard timer.showControls, timer.cardExpanded, let panel else { return }
        let needed = frame(expanded: true, controlsHeight: timer.tallestControls)
        if needed.height > panel.frame.height { panel.setFrame(needed, display: true) }
    }

    private func removeMonitor() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }

    func hide(after seconds: Double = 0, timer: EyeTimer) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            if seconds > 0 {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
            guard !Task.isCancelled, let self else { return }
            timer.cardExpanded = false
            timer.showControls = false
            self.removeMonitor()
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self.panel?.setFrame(self.frame(expanded: false), display: true)
            if self.hiddenForFullscreen { self.panel?.orderOut(nil) }
        }
    }
}
