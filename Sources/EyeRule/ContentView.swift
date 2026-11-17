import SwiftUI

struct ContentView: View {
    @ObservedObject var timer: EyeTimer

    var body: some View {
        VStack(spacing: 14) {
            RingView(progress: timer.progress, text: timer.label,
                     color: timer.phase == .resting ? .green : .accentColor)
            Text(timer.message)
                .font(.system(.body, design: .rounded))
                .multilineTextAlignment(.center)
            if timer.breaksToday > 0 {
                Text("Nice. \(timer.breaksToday) break\(timer.breaksToday == 1 ? "" : "s") today.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button(timer.isRunning ? "Pause" : "Resume") { timer.toggle() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Menu {
                    Button("Break now") { timer.startBreakNow() }
                    Button("Reset timer") { timer.reset() }
                    Button("Stats and settings") { timer.openControls() }
                    Divider()
                    Picker("Reminder", selection: $timer.mode) {
                        ForEach(NotifyMode.allCases) { Text($0.title).tag($0) }
                    }
                    Divider()
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(20)
        .frame(width: 260)
    }
}
