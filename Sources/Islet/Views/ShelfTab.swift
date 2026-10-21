import SwiftUI
import UniformTypeIdentifiers

struct ShelfTab: View {
    let model: IslandModel

    var body: some View {
        let shelf = model.shelf
        let targeted = model.isDropTargeted
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .foregroundStyle(targeted ? Color.accentColor : .white.opacity(0.22))
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(targeted ? Color.accentColor.opacity(0.12) : .clear))

                if shelf.items.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(.system(size: 26))
                            .symbolEffect(.bounce, value: targeted)
                        Text("Drop files on the notch to keep them here")
                            .font(.system(size: 12.5, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(targeted ? 0.9 : 0.5))
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(shelf.items) { item in
                                ShelfItemView(item: item, thumbnail: shelf.thumbnails[item.url]) {
                                    shelf.remove(item)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    .scrollIndicators(.never)
                }
            }

            if !shelf.items.isEmpty {
                VStack(spacing: 6) {
                    IconButton(symbol: "airplayaudio", size: 13, help: "AirDrop all") { shelf.airDropAll() }
                    IconButton(symbol: "xmark.bin", size: 13, help: "Clear shelf") { shelf.clear() }
                    Spacer()
                    Text("\(shelf.items.count)")
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
        }
    }
}

private struct ShelfItemView: View {
    let item: ShelfStore.Item
    let thumbnail: NSImage?
    let onRemove: () -> Void

    @ViewState private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "doc.fill").font(.system(size: 30))
                }
            }
            .frame(width: 54, height: 54)
            Text(item.url.lastPathComponent)
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 74)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(hovering ? 0.1 : 0)))
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 14))
                        .foregroundStyle(.white, .gray)
                }
                .buttonStyle(.plain)
            }
        }
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(item.url) }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .help(item.url.path)
    }
}
