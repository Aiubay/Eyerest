import AppKit
import SwiftUI

/// Rounded only at the bottom, so the top blends into the screen edge and notch.
struct NotchShape: Shape {
    var radius: CGFloat
    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }
    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.height / 2, rect.width / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r,
                 startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
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

enum ControlsTab: String, CaseIterable {
    case timer = "Timer", stats = "Stats", settings = "Settings"

    /// Panel height below the menu bar for each tab.
    var height: CGFloat {
        switch self {
        case .timer: return 210
        case .stats: return 350
        case .settings: return 445
        }
    }
}

struct BreakCardView: View {
    @ObservedObject var timer: EyeTimer
    let topInset: CGFloat
    let notchWidth: CGFloat
    let pillWidth: CGFloat

    @State private var pulse = false
    @State private var breathe = false
    @State private var eyeClosed = false
    @State private var shimmer: CGFloat = -0.2
    @State private var tab: ControlsTab = .timer

    private var wing: CGFloat { (pillWidth - notchWidth) / 2 }
    private var expanded: Bool { timer.cardExpanded }
    private var expandedHeight: CGFloat {
        topInset + (timer.showControls ? timer.controlsHeight : BreakCardController.contentHeight)
    }

    var body: some View {
        ZStack(alignment: .top) {
            NotchShape(radius: expanded ? 30 : topInset / 2).fill(Color.black)
            NotchShape(radius: expanded ? 30 : topInset / 2)
                .stroke(timer.accent.opacity(edgeOpacity), lineWidth: 1.5)
            if expanded {
                Group {
                    if timer.showControls { controlsContent } else { breakContent }
                }
                .transition(.opacity)
            } else {
                compactContent.transition(.opacity)
            }
        }
        .frame(width: pillWidth, height: expanded ? expandedHeight : topInset)
        .clipShape(NotchShape(radius: expanded ? 30 : topInset / 2))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.5, dampingFraction: 0.55), value: expanded)
        .animation(.spring(response: 0.45, dampingFraction: 0.78), value: timer.showControls)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: timer.controlsHeight)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { breathe = true }
            withAnimation(.linear(duration: 2.6).repeatForever(autoreverses: false)) { shimmer = 1.1 }
        }
        .onChange(of: timer.showControls) { _ in tab = .timer }
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

    private var edgeOpacity: Double {
        if timer.phase == .resting || timer.isUrgent { return pulse ? 0.95 : 0.25 }
        return 0.4
    }

    // MARK: Compact pill

    private var compactIcon: String {
        if timer.autoPaused { return "moon.zzz.fill" }
        if !timer.isRunning { return "pause.fill" }
        return "eye.fill"
    }

    private var compactContent: some View {
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
        .frame(height: topInset)
        .overlay(alignment: .bottom) { progressLine }
        .contentShape(Rectangle())
        .onTapGesture { timer.openControls() }
    }

    private var progressLine: some View {
        GeometryReader { geo in
            let fill = geo.size.width * min(max(timer.progress, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(timer.accent)
                    .frame(width: fill)
                    .overlay(alignment: .leading) {
                        LinearGradient(colors: [.clear, .white.opacity(0.7), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: 36)
                            .offset(x: fill * shimmer - 18)
                    }
                    .clipShape(Capsule())
            }
        }
        .frame(height: 3)
        .padding(.horizontal, topInset / 2)
        .padding(.bottom, 4)
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
        .padding(.top, topInset + 8)
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
            Group {
                switch tab {
                case .timer: timerTab
                case .stats: statsTab
                case .settings: settingsTab
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, topInset + 8)
        .environment(\.colorScheme, .dark)
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(ControlsTab.allCases, id: \.self) { t in
                Button(t.rawValue) { tab = t; timer.controlsHeight = t.height }
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
                toggleRow("Launch at login", $timer.launchAtLogin)
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
