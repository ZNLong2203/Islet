import SwiftUI

struct HomeTab: View {
    let model: IslandModel

    var body: some View {
        HStack(spacing: 18) {
            MediaCard(media: model.media)
                .frame(maxWidth: .infinity)
            Rectangle().fill(.white.opacity(0.08)).frame(width: 1)
            CalendarCard(calendar: model.calendar)
                .frame(width: 150)
        }
    }
}

private struct MediaCard: View {
    let media: NowPlayingService

    var body: some View {
        if media.hasMedia {
            HStack(spacing: 16) {
                artwork
                VStack(alignment: .leading, spacing: 4) {
                    MarqueeText(text: media.title, font: .system(size: 15, weight: .semibold), height: 19)
                    Text(media.artist.isEmpty ? media.album : media.artist)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    ScrubBar(media: media)
                    controls
                }
            }
        } else {
            HStack(spacing: 14) {
                ArtworkView(image: nil, size: 86, corner: 16).opacity(0.5)
                VStack(alignment: .leading, spacing: 8) {
                    Text(media.isAvailable ? String(localized: "Nothing playing") : String(localized: "Can't read Now Playing"))
                        .font(.system(size: 14, weight: .semibold))
                    Text("Play something in Music, Spotify or YouTube and it shows up here.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Music") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Music.app"))
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(.white.opacity(0.14)))
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var artwork: some View {
        ArtworkView(image: media.artwork, size: 96, corner: 18)
            .shadow(color: media.accent.opacity(0.55), radius: 16)
            .overlay(alignment: .bottomTrailing) {
                if let icon = media.playerIcon {
                    Image(nsImage: icon).resizable().frame(width: 26, height: 26).offset(x: 7, y: 7)
                }
            }
            .scaleEffect(media.isPlaying ? 1 : 0.92)
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: media.isPlaying)
            .onTapGesture { media.openPlayerApp() }
            .help("Open the playing app")
    }

    private var controls: some View {
        HStack(spacing: 18) {
            IconButton(symbol: "backward.fill", size: 15) { media.previous() }
            IconButton(symbol: media.isPlaying ? "pause.fill" : "play.fill", size: 22) { media.togglePlayPause() }
                .contentTransition(.symbolEffect(.replace))
            IconButton(symbol: "forward.fill", size: 15) { media.next() }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Playback position with drag-to-seek.
private struct ScrubBar: View {
    let media: NowPlayingService

    @ViewState private var dragProgress: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let elapsed = media.elapsed(at: context.date)
            let progress = dragProgress ?? (media.duration > 0 ? elapsed / media.duration : 0)
            HStack(spacing: 8) {
                Text(format(dragProgress.map { $0 * media.duration } ?? elapsed))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18))
                        Capsule().fill(media.accent).frame(width: geo.size.width * progress)
                    }
                    .frame(height: dragProgress == nil ? 4 : 7)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { dragProgress = min(max($0.location.x / geo.size.width, 0), 1) }
                        .onEnded { _ in
                            if let p = dragProgress { media.seek(to: p * media.duration) }
                            dragProgress = nil
                        })
                }
                .frame(height: 12)
                Text("-" + format(max(0, media.duration - elapsed)))
            }
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.5))
            .animation(.spring(response: 0.25), value: dragProgress == nil)
        }
    }

    private func format(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

private struct CalendarCard: View {
    let calendar: CalendarService

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 2) {
                Text(context.date.formatted(.dateTime.weekday(.wide)).uppercased())
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.red)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(context.date.formatted(.dateTime.day()))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text(context.date.formatted(.dateTime.hour().minute()))
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer(minLength: 2)
                if !calendar.isAuthorized {
                    Button {
                        calendar.requestAccess()
                    } label: {
                        Label("Connect Calendar", systemImage: "calendar.badge.plus")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.7))
                } else if calendar.events.isEmpty {
                    Text("Nothing else today 🎉")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                } else {
                    ForEach(calendar.events.prefix(2)) { event in
                        HStack(spacing: 6) {
                            Capsule().fill(event.color).frame(width: 3, height: 26)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(event.title).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                                Text(event.isAllDay ? String(localized: "All day") : event.start.formatted(.dateTime.hour().minute()))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
