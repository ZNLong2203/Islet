import SwiftUI

/// Live activity beside the notch: album art + visualizer, and/or the focus timer.
struct CompactWingsView: View {
    let model: IslandModel

    var body: some View {
        let media = model.media
        let timer = model.timer
        WingsLayout(notchWidth: model.notchSize.width, height: model.notchSize.height) {
            if media.showsActivity {
                ArtworkView(image: media.artwork, size: 20, corner: 5)
            } else {
                ProgressRing(progress: timer.progress, color: .orange, lineWidth: 2.5)
                    .frame(width: 16, height: 16)
            }
        } trailing: {
            if timer.isActive {
                Text(timer.remainingText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.orange)
                    .contentTransition(.numericText(countsDown: true))
            } else {
                WaveformView(isPlaying: media.isPlaying, color: media.accent)
            }
        }
    }
}

struct PeekView: View {
    let kind: PeekKind
    let model: IslandModel

    var body: some View {
        switch kind {
        case .power(let plugged):
            let color: Color = plugged ? .green : .white
            WingsLayout(notchWidth: model.notchSize.width, height: model.notchSize.height) {
                PeekLabel(kind: kind, color: color)
            } trailing: {
                BatteryBadge(level: model.battery.level, charging: plugged, tint: color)
            }

        case .lowBattery:
            WingsLayout(notchWidth: model.notchSize.width, height: model.notchSize.height) {
                PeekLabel(kind: kind, color: .red)
            } trailing: {
                BatteryBadge(level: model.battery.level, charging: false, tint: .red)
            }

        case .timerFinished:
            WingsLayout(notchWidth: model.notchSize.width, height: model.notchSize.height) {
                PeekLabel(kind: kind, color: .orange, bounces: 3)
            } trailing: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.green)
            }

        case .nowPlaying:
            VStack(spacing: 0) {
                Color.clear.frame(height: model.notchSize.height)
                HStack(spacing: 10) {
                    ArtworkView(image: model.media.artwork, size: 36, corner: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.media.title)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Text(model.media.artist)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    WaveformView(isPlaying: model.media.isPlaying, color: model.media.accent)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 10)
                .frame(maxHeight: .infinity)
            }
        }
    }
}

/// Icon + title for banner peeks. Its metrics mirror `IslandModel.peekWingWidth`, which sizes the island to fit.
private struct PeekLabel: View {
    let kind: PeekKind
    let color: Color
    var bounces = 1

    var body: some View {
        HStack(spacing: Metrics.peekIconSpacing) {
            Image(systemName: kind.symbol)
                .frame(width: Metrics.peekIconWidth)
                .symbolEffect(.bounce, options: .repeat(bounces), value: kind)
            Text(kind.title)
                .lineLimit(1)
                .fixedSize()
        }
        .font(.system(size: Metrics.peekFontSize, weight: .semibold))
        .foregroundStyle(color)
    }
}
