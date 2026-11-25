import AppKit
import SwiftUI

/// Rounded only at the bottom, so the top blends into the screen edge and notch.
struct NotchShape: Shape {
    var radius: CGFloat
    /// Floating islands (Macs without a notch) round the top corners too.
    var roundTop = false
    /// Notch islands flare outward at the top, so the black blends into the screen edge.
    var flare: CGFloat = 0
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(radius, flare) }
        set { radius = newValue.first; flare = newValue.second }
    }
    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.height / 2, (rect.width - 2 * flare) / 2)
        var p = Path()
        if roundTop {
            p.addRoundedRect(in: rect, cornerSize: CGSize(width: r, height: r), style: .continuous)
            return p
        }
        let f = flare
        // Control-point ratio for a cubic that traces a quarter circle.
        let k: CGFloat = 0.55228475
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        if f > 0 {
            p.addCurve(to: CGPoint(x: rect.maxX - f, y: rect.minY + f),
                       control1: CGPoint(x: rect.maxX - f * k, y: rect.minY),
                       control2: CGPoint(x: rect.maxX - f, y: rect.minY + f * (1 - k)))
        }
        p.addLine(to: CGPoint(x: rect.maxX - f, y: rect.maxY - r))
        p.addArc(center: CGPoint(x: rect.maxX - f - r, y: rect.maxY - r), radius: r,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + f + r, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + f + r, y: rect.maxY - r), radius: r,
                 startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        if f > 0 {
            p.addLine(to: CGPoint(x: rect.minX + f, y: rect.minY + f))
            p.addCurve(to: CGPoint(x: rect.minX, y: rect.minY),
                       control1: CGPoint(x: rect.minX + f, y: rect.minY + f * (1 - k)),
                       control2: CGPoint(x: rect.minX + f * k, y: rect.minY))
        }
        p.closeSubpath()
        return p
    }
}

struct PillButtonStyle: ButtonStyle {
    var prominent = false
    var small = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: small ? 12 : 13, weight: .semibold, design: .rounded))
            .foregroundStyle(prominent ? .black : .white)
            .padding(.horizontal, small ? 11 : 14)
            .padding(.vertical, small ? 6 : 7)
            .background(Capsule().fill(prominent ? Color.white : Color.white.opacity(0.15)))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Content heights reported by the (hidden) measuring copies of each tab.
struct TabHeightKey: PreferenceKey {
    static var defaultValue: [ControlsTab: CGFloat] = [:]
    static func reduce(value: inout [ControlsTab: CGFloat], nextValue: () -> [ControlsTab: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Blur plus fade between tabs, similar to `.blurReplace` (macOS 14+).
struct BlurFade: ViewModifier {
    let amount: Double
    var blurs = true
    func body(content: Content) -> some View {
        content.blur(radius: blurs ? 6 * amount : 0).opacity(1 - amount)
    }
}

enum ControlsTab: String, CaseIterable {
    case timer = "Timer", stats = "Stats", settings = "Settings"

    /// First-guess panel height below the menu bar, used until the real content has been measured.
    var height: CGFloat {
        switch self {
        case .timer: return 195
        case .stats: return 300
        case .settings: return 400
        }
    }
}

struct BreakCardView: View {
    @ObservedObject var timer: EyeTimer
    let topInset: CGFloat
    /// Height of the resting strip: the camera housing's own height beside a notch.
    let restingHeight: CGFloat
    let notchWidth: CGFloat
    let pillWidth: CGFloat
    let compactWidth: CGFloat
    /// True on Macs without a notch: a detached island that hovers below the top edge.
    var floating = false

    @State private var hoverTask: Task<Void, Never>?
    @State private var hoverOpened = false
    @State private var hovering = false
    @State private var pressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    @State private var breathe = false
    @State private var eyeClosed = false
    @State private var tab: ControlsTab = .timer

    /// Shoulder at the top corners. The resting strip keeps small ones, as the notch itself has.
    private var flare: CGFloat {
        if floating { return 0 }
        return expanded ? BreakCardController.flare : min(BreakCardController.flare, compactHeight * 0.19)
    }
    /// One spring for expand, collapse, hover and press, so the island moves as a single object.
    private static let islandSpring = Animation.spring(response: 0.48, dampingFraction: 0.76, blendDuration: 0.3)

    private var wing: CGFloat { (compactWidth - 2 * flare - notchWidth) / 2 }
    private var expanded: Bool { timer.cardExpanded }
    /// Space above expanded content. A notch or menu bar must be cleared; a floating island needs little.
    private var headroom: CGFloat { floating ? BreakCardController.floatingHeadroom : topInset }
    private var islandWidth: CGFloat {
        if expanded { return pillWidth }
        let base = floating ? BreakCardController.floatingCompactWidth : compactWidth
        return base + (hovering ? BreakCardController.hoverGrowWidth : 0)
    }
    private var islandHeight: CGFloat {
        expanded ? expandedHeight : compactHeight + (hovering ? BreakCardController.hoverGrowHeight : 0)
    }
    private var compactHeight: CGFloat {
        floating ? topInset : restingHeight
    }
    private var shape: NotchShape {
        NotchShape(radius: expanded ? 28 : (floating ? topInset / 2 : compactHeight * 0.34), roundTop: floating, flare: flare)
    }
    private var expandedHeight: CGFloat {
        headroom + (timer.showControls ? timer.controlsHeight : BreakCardController.contentHeight)
    }

    var body: some View {
        ZStack(alignment: .top) {
            shape.fill(Color.black)
            if expanded {
                Group {
                    if timer.showControls { controlsContent } else { breakContent }
                }
                .padding(.horizontal, flare)
                .transition(.opacity)
            } else {
                compactContent
                    .padding(.horizontal, flare)
                    .transition(.opacity)
            }
        }
        .frame(width: islandWidth, height: islandHeight, alignment: .top)
        .clipShape(shape)
        .scaleEffect(pressed ? 0.96 : 1, anchor: .top)
        .onHover(perform: handleHover)
        .simultaneousGesture(
            DragGesture(minimumDistance: 24).onEnded { value in
                // Swipe up to dismiss the controls.
                if timer.showControls && value.translation.height < -40 { timer.closeControls() }
            }
        )
        .padding(.top, floating ? BreakCardController.floatingGap : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Self.islandSpring, value: expanded)
        .animation(Self.islandSpring, value: pressed)
        .animation(Self.islandSpring, value: hovering)
        .animation(.spring(response: 0.45, dampingFraction: 0.78), value: timer.showControls)
                .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { breathe = true }
        }
        .onChange(of: timer.showControls) { open in
            tab = .timer
            if !open { hoverOpened = false }
        }
        .task {
            // Blink the idle eye every few seconds.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64.random(in: 3_000_000_000...7_000_000_000))
                withAnimation(.easeIn(duration: 0.08)) { eyeClosed = true }
                try? await Task.sleep(nanoseconds: 140_000_000)
                withAnimation(.easeOut(duration: 0.12)) { eyeClosed = false }
            }
        }
    }

    /// Hovering grows the compact island a little. On a floating island it also opens the controls, leaving closes them again.
    /// Controls opened by a click or a break card are left alone.
    private func handleHover(_ inside: Bool) {
        hovering = inside
        guard floating else { return }
        hoverTask?.cancel()
        if inside {
            guard !expanded else { return }
            hoverTask = Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled, !timer.cardExpanded else { return }
                hoverOpened = true
                timer.openControls()
            }
        } else if hoverOpened {
            hoverTask = Task {
                try? await Task.sleep(nanoseconds: 450_000_000)
                guard !Task.isCancelled, timer.showControls else { return }
                hoverOpened = false
                timer.closeControls()
            }
        }
    }

    // MARK: Compact pill

    private var compactIcon: String {
        if timer.autoPaused { return "moon.zzz.fill" }
        if timer.deferred { return "phone.fill" }
        if !timer.isRunning { return "pause.fill" }
        return "eye.fill"
    }

    private var compactContent: some View {
        compactLayout
            .frame(height: compactHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in pressed = true }
                    .onEnded { value in
                        pressed = false
                        if abs(value.translation.width) < 6 && abs(value.translation.height) < 6 {
                            timer.openControls()
                        }
                    }
            )
            .contextMenu {
                Button(timer.isRunning ? "Pause" : "Resume") { timer.toggle() }
                Button("Break now") { timer.startBreakNow() }
                Button("Reset timer") { timer.reset() }
                Divider()
                Button("Quit EyeRule") { NSApplication.shared.terminate(nil) }
            }
    }

    private var compactIconView: some View {
        Image(systemName: compactIcon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(timer.accent)
            .opacity(timer.isUrgent && pulse ? 0.35 : 1)
            .scaleEffect(x: 1, y: (eyeClosed && timer.isActive) ? 0.1 : 1)
    }

    private var compactTextView: some View {
        HStack(spacing: 5) {
            if timer.cameraActive {
                Image(systemName: "camera.fill")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Text(timer.compactLabel)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .monospacedDigit()
                .foregroundStyle(timer.isActive ? .white : .white.opacity(0.5))
        }
    }

    @ViewBuilder private var compactLayout: some View {
        if floating {
            HStack(spacing: 0) {
                compactIconView
                Spacer(minLength: 8)
                compactTextView
            }
            .padding(.horizontal, 16)
        } else {
            notchedCompactLayout
        }
    }

    private var notchedCompactLayout: some View {
        HStack(spacing: 0) {
            Image(systemName: compactIcon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(timer.accent)
                .opacity(timer.isUrgent && pulse ? 0.35 : 1)
                .scaleEffect(x: 1, y: (eyeClosed && timer.isActive) ? 0.1 : 1)
                .frame(width: wing)
            Spacer().frame(width: notchWidth)
            ZStack(alignment: .trailing) {
                Text(timer.compactLabel)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .monospacedDigit()
                    .foregroundStyle(timer.isActive ? .white : .white.opacity(0.5))
                if timer.cameraActive {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(width: wing)
        }
    }

    // MARK: Break

    private var breakContent: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                RingView(progress: timer.showDone ? 1 : timer.progress,
                         text: timer.showDone ? "✓" : "\(timer.remaining)",
                         size: 58, color: .green)
                    .foregroundStyle(.white)
                    .scaleEffect(timer.showDone ? 1 : (breathe ? 1.06 : 0.97))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Image(systemName: "eye.fill")
                            .foregroundStyle(.green)
                            .scaleEffect(breathe ? 1.3 : 0.9)
                        Text(timer.showDone ? "Nice, eyes rested." : "Look 20 feet away")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    Text(timer.showDone ? doneSubtitle : timer.prompt)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if !timer.showDone {
                HStack(spacing: 8) {
                    if timer.cameraActive {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.green.opacity(0.85))
                    }
                    Button(timer.blinks >= 10 ? "Blinked ✓" : "Blink \(timer.blinks)/10") { timer.blink() }
                        .buttonStyle(PillButtonStyle(prominent: timer.blinks < 10, small: true))
                    Button("Skip") { timer.skipBreak() }
                        .buttonStyle(PillButtonStyle(small: true))
                    Button("5 more min") { timer.snooze() }
                        .buttonStyle(PillButtonStyle(small: true))
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, headroom + 8)
    }

    private var doneSubtitle: String {
        var s = "\(timer.breaksToday) of \(timer.dailyGoal) today"
        if timer.streak > 1 { s += " · \(timer.streak)-day streak" }
        return s
    }

    // MARK: Controls

    private var controlsContent: some View {
        VStack(spacing: 12) {
            tabBar
            tabPages
        }
        // The stacked tabs are as tall as Settings. Pin to the top so a shorter
        // island clips the bottom, never the tab bar.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 24)
        .padding(.top, headroom + 8)
        .environment(\.colorScheme, .dark)
    }

    /// Every tab stays mounted, stacked in place; only the selected one is visible.
    /// Inserting Settings during the animation made its AppKit-backed switches,
    /// steppers and pickers animate their frames in from the middle.
    private var tabPages: some View {
        ZStack(alignment: .top) {
            ForEach(ControlsTab.allCases, id: \.self) { t in
                page(t)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: TabHeightKey.self, value: [t: geo.size.height])
                    })
                    .modifier(BlurFade(amount: tab == t ? 0 : 1, blurs: !reduceMotion))
                    .allowsHitTesting(tab == t)
                    .accessibilityHidden(tab != t)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .onPreferenceChange(TabHeightKey.self) { heights in
            // Tab bar, spacing and padding around the content.
            let extra: CGFloat = 8 + 28 + 12 + 20
            var fitted: [ControlsTab: CGFloat] = [:]
            for (t, h) in heights where h > 0 { fitted[t] = (h + extra).rounded(.up) }
            guard !fitted.isEmpty else { return }
            timer.tabHeights.merge(fitted) { $1 }
            timer.reserveControls()
            if let h = fitted[tab], timer.showControls, abs(h - timer.controlsHeight) > 0.5 {
                withAnimation(tabMotion) { timer.controlsHeight = h }
            }
        }
    }

    /// Tab changes: a short spring with no bounce, as Vorssaint uses for its paging.
    private var tabMotion: Animation? {
        reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1.0)
    }

    @ViewBuilder private func page(_ t: ControlsTab) -> some View {
        switch t {
        case .timer: timerTab
        case .stats: statsTab
        case .settings: settingsTab
        }
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(ControlsTab.allCases, id: \.self) { t in
                Button(t.rawValue) {
                    guard tab != t else { return }
                    // Content and height move in one transaction, inside a window that is already big enough.
                    withAnimation(tabMotion) {
                        tab = t
                        timer.controlsHeight = timer.height(for: t)
                    }
                }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(tab == t ? .white : .white.opacity(0.5))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(tab == t ? Color.white.opacity(0.18) : .clear))
            }
        }
    }

    private var timerTab: some View {
        VStack(spacing: 16) {
            HStack(spacing: 18) {
                RingView(progress: timer.progress, text: timer.label, size: 92, color: timer.accent)
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 4) {
                    Text(statusWord)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.5))
                    Text(timer.message)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(timer.breaksToday == 0
                         ? "No breaks yet today."
                         : "\(timer.breaksToday) break\(timer.breaksToday == 1 ? "" : "s") today.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Button(timer.isRunning ? "Pause" : "Resume") { timer.toggle() }
                    .buttonStyle(PillButtonStyle(prominent: true))
                Button("Break now") { timer.startBreakNow() }
                    .buttonStyle(PillButtonStyle())
                Button("Reset") { timer.reset() }
                    .buttonStyle(PillButtonStyle())
                Spacer(minLength: 0)
            }
        }
    }

    private var statusWord: String {
        if timer.phase == .resting { return "BREAK" }
        if !timer.isRunning { return "PAUSED" }
        if timer.autoPaused { return "AWAY" }
        if timer.deferred { return "IN A CALL" }
        return "WORKING"
    }

    private var statsTab: some View {
        let days = timer.lastSevenDays
        let week = timer.weeklyInsights
        let maxValue = max(days.map(\.count).max() ?? 1, timer.dailyGoal, 1)
        return VStack(spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(timer.breaksToday) of \(timer.dailyGoal) today")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(.white)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.12))
                            Capsule().fill(timer.accent)
                                .frame(width: geo.size.width * min(1, Double(timer.breaksToday) / Double(max(timer.dailyGoal, 1))))
                        }
                    }
                    .frame(width: 150, height: 6)
                }
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "flame.fill").foregroundStyle(.orange)
                    Text("\(timer.streak)-day streak")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(days) { day in
                    VStack(spacing: 4) {
                        Spacer(minLength: 0)
                        Capsule()
                            .fill(day.isToday ? timer.accent : Color.white.opacity(0.25))
                            .frame(height: max(4, 46 * CGFloat(day.count) / CGFloat(maxValue)))
                        Text(day.label)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(day.isToday ? 0.9 : 0.5))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 68)
            VStack(alignment: .leading, spacing: 8) {
                Text("Last 7 days")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                HStack {
                    insightMetric("Completed", value: "\(week.completed)")
                    insightMetric("Skipped", value: "\(week.skipped)")
                    insightMetric("Break time", value: "\(week.seconds / 60)m \(week.seconds % 60)s")
                }
                Text(timer.weeklyComparison)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                Text("Skips and break time tracked since \(timer.insights.trackingStarted.formatted(.dateTime.month(.abbreviated).day())).")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func insightMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(title)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var settingsTab: some View {
        VStack(spacing: 9) {
            HStack(spacing: 18) {
                stepperRow("Work", value: $timer.workMinutes, range: 5...60, step: 5, unit: " min")
                stepperRow("Break", value: $timer.breakSeconds, range: 10...60, step: 5, unit: " s")
            }
            HStack(spacing: 18) {
                stepperRow("Goal", value: $timer.dailyGoal, range: 5...50, step: 5, unit: "")
                HStack {
                    label("Sound")
                    Spacer()
                    Picker("", selection: $timer.soundTheme) {
                        ForEach(SoundTheme.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .onChange(of: timer.soundTheme) { _ in timer.previewSound() }
                }
                .frame(maxWidth: .infinity)
            }
            HStack {
                label("Reminder")
                Picker("", selection: $timer.mode) {
                    ForEach(NotifyMode.allCases) { Text($0.shortTitle).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 190)
                Spacer(minLength: 0)
            }
            toggleRow("Dim screen during breaks", $timer.dimScreenDuringBreaks)
            Text("Esc dismisses dimming. Skipped in calls and fullscreen apps.")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 18) {
                toggleRow("Smart pause", $timer.smartPause)
                toggleRow("Wait in calls", $timer.meetingMode)
            }
            HStack(spacing: 18) {
                toggleRow("Camera blinks", $timer.cameraEnabled)
                HStack {
                    Spacer()
                    if timer.cameraStatus != nil {
                        Button("Camera settings") { openCameraSettings() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                .frame(maxWidth: .infinity)
            }
            if let status = timer.cameraStatus {
                Text(status)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(timer.cameraActive ? .green.opacity(0.8) : .white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 18) {
                toggleRow("Camera pause", $timer.cameraPresencePause)
                toggleRow("Blink reminder", $timer.blinkReminderEnabled)
            }
            HStack(spacing: 18) {
                stepperRow("Blink warning below", value: $timer.blinkRateThreshold,
                           range: 5...25, step: 5, unit: "/min")
            }
            HStack(spacing: 18) {
                toggleRow("Hide in fullscreen", $timer.hideInFullscreen)
                toggleRow("Launch at login", $timer.launchAtLogin)
            }
            HStack(spacing: 18) {
                Text("Breaks still appear over fullscreen apps.")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Spacer()
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .frame(maxWidth: .infinity)
            }
            if let note = timer.launchNote {
                Text(note)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.orange)
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, design: .rounded))
            .foregroundStyle(.white.opacity(0.65))
    }

    private func stepperRow(_ title: String, value: Binding<Int>, range: ClosedRange<Int>,
                            step: Int, unit: String) -> some View {
        HStack(spacing: 6) {
            label(title)
            Spacer(minLength: 0)
            Text("\(value.wrappedValue)\(unit)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
            Stepper("", value: value, in: range, step: step).labelsHidden()
        }
        .frame(maxWidth: .infinity)
    }

    private func toggleRow(_ title: String, _ binding: Binding<Bool>) -> some View {
        HStack {
            label(title)
            Spacer(minLength: 0)
            Toggle("", isOn: binding).labelsHidden().toggleStyle(.switch).controlSize(.mini)
                .accessibilityLabel(title)
        }
        .frame(maxWidth: .infinity)
    }

    private func openCameraSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }
}
