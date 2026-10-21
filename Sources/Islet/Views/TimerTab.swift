import SwiftUI

struct TimerTab: View {
    let timer: FocusTimer

    private let presets = [5, 15, 25, 45]

    var body: some View {
        HStack(spacing: 26) {
            ZStack {
                ProgressRing(progress: timer.progress, color: .orange, lineWidth: 7)
                Text(timer.remainingText)
                    .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText(countsDown: true))
            }
            .frame(width: 104, height: 104)

            VStack(alignment: .leading, spacing: 14) {
                Text("Focus")
                    .font(.system(size: 15, weight: .semibold))
                HStack(spacing: 8) {
                    ForEach(presets, id: \.self) { minutes in
                        let selected = Int(timer.duration) == minutes * 60
                        Button("\(minutes)′") { timer.set(minutes: minutes) }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(selected ? Color.orange.opacity(0.3) : .white.opacity(0.1)))
                            .foregroundStyle(selected ? .orange : .white)
                    }
                }
                HStack(spacing: 10) {
                    Button(action: timer.toggle) {
                        Label(timer.isRunning ? String(localized: "Pause") : String(localized: "Start"),
                              systemImage: timer.isRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 16).padding(.vertical, 7)
                            .background(Capsule().fill(.orange))
                            .foregroundStyle(.black)
                    }
                    .buttonStyle(.plain)
                    if timer.isActive {
                        IconButton(symbol: "arrow.counterclockwise", size: 13, help: "Reset") { timer.reset() }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}
