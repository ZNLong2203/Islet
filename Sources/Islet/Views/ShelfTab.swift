import SwiftUI

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
                        Text("Tip: shake a file while dragging it to open a drop zone anywhere")
                            .font(.system(size: 10.5))
                            .opacity(0.7)
                    }
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(targeted ? 0.9 : 0.5))
                    .padding(.horizontal, 12)
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(shelf.items) { item in
                                ShelfTile(item: item, model: model)
                            }
                        }
                        .padding(.horizontal, 10)
                    }
                    .scrollIndicators(.never)
                }
            }

            actions(shelf)
        }
        .onAppear { shelf.prune() }
    }

    private func actions(_ shelf: ShelfStore) -> some View {
        let hasItems = !shelf.items.isEmpty
        return VStack(spacing: 4) {
            LazyVGrid(columns: [GridItem(.fixed(28), spacing: 4), GridItem(.fixed(28), spacing: 4)], spacing: 4) {
                IconButton(symbol: "doc.on.clipboard", size: 12, help: "Add from clipboard (⌃⌥V)") { shelf.addFromPasteboard() }
                IconButton(symbol: "square.and.arrow.up", size: 12, help: "Share selected, or all") {
                    ShelfMenus.showSharePicker(for: shelf.targets.map(\.url), model: model)
                }
                .disabled(!hasItems)
                IconButton(symbol: "airplayaudio", size: 12, help: "AirDrop selected, or all") { shelf.airDrop(shelf.targets) }
                    .disabled(!hasItems)
                IconButton(symbol: "doc.on.doc", size: 12, help: "Copy selected, or all") { shelf.copyToClipboard(shelf.targets) }
                    .disabled(!hasItems)
                Group {
                    if shelf.isBusy {
                        ProgressView().controlSize(.small).frame(width: 28, height: 28)
                    } else {
                        IconButton(symbol: "doc.zipper", size: 12, help: "Zip selected, or all") { shelf.zip(shelf.targets) }
                            .disabled(!hasItems)
                    }
                }
                IconButton(symbol: "xmark.bin", size: 12, help: "Remove selected, or all") { shelf.removeTargets() }
                    .disabled(!hasItems)
            }
            .opacity(hasItems ? 1 : 0.7)
            Spacer(minLength: 0)
            if hasItems {
                Text(shelf.selection.isEmpty
                     ? String(localized: "\(shelf.items.count) items")
                     : String(localized: "\(shelf.targets.count) of \(shelf.items.count) selected"))
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .frame(width: 60)
            }
        }
        .frame(width: 60)
    }
}

private struct ShelfTile: View {
    let item: ShelfStore.Item
    let model: IslandModel

    @ViewState private var hovering = false

    var body: some View {
        let shelf = model.shelf
        let isSelected = shelf.selection.contains(item.id)
        VStack(spacing: 4) {
            Group {
                if let thumbnail = shelf.thumbnails[item.url] {
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
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(isSelected ? 0.16 : (hovering ? 0.1 : 0))))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor, lineWidth: 1.5).opacity(isSelected ? 1 : 0))
        .overlay {
            ShelfTileSurface(
                toolTip: item.url.path,
                dragURLs: { dragTargets().map(\.url) },
                onClick: { shelf.toggleSelection(item) },
                onOpen: { shelf.open(item) },
                onHover: { hovering = $0 },
                onDragBegan: { model.isDraggingOut = true },
                onDragEnded: { delivered, urls in
                    model.isDraggingOut = false
                    if delivered { shelf.finishedDragOut(urls) }
                },
                menu: { contextMenu() })
        }
        .overlay(alignment: .topLeading) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.accentColor)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button { shelf.remove(item) } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 14))
                        .foregroundStyle(.white, .gray)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Dragging a selected tile takes the whole selection; any other tile goes alone.
    private func dragTargets() -> [ShelfStore.Item] {
        model.shelf.selection.contains(item.id) ? model.shelf.targets : [item]
    }

    private func contextMenu() -> NSMenu {
        let shelf = model.shelf
        let targets = dragTargets()
        let menu = NSMenu()
        menu.addItem(BlockMenuItem(String(localized: "Open"), symbol: "arrow.up.forward.app") { targets.forEach(shelf.open) })
        menu.addItem(BlockMenuItem(String(localized: "Show in Finder"), symbol: "folder") { shelf.reveal(targets) })
        menu.addItem(.separator())
        menu.addItem(BlockMenuItem(String(localized: "Copy"), symbol: "doc.on.doc") { shelf.copyToClipboard(targets) })
        menu.addItem(BlockMenuItem(String(localized: "Zip"), symbol: "doc.zipper") { shelf.zip(targets) })
        menu.addItem(ShelfMenus.shareItem(for: targets.map(\.url)))
        menu.addItem(.separator())
        menu.addItem(BlockMenuItem(String(localized: "Remove from Shelf"), symbol: "xmark") { shelf.remove(Set(targets.map(\.id))) })
        return menu
    }
}

/// The system's sharing UI (Messages, Mail, Notes, AirDrop…), which works inside the island's panel.
@MainActor
enum ShelfMenus {
    /// The picker owns its menu items' actions, so it has to outlive the menu or popover.
    private static var picker: NSSharingServicePicker?
    private static let pickerDelegate = PickerDelegate()

    /// The system's own "Share" item. macOS fills in its submenu when the menu opens.
    static func shareItem(for urls: [URL]) -> NSMenuItem {
        let picker = NSSharingServicePicker(items: urls)
        self.picker = picker
        return picker.standardShareMenuItem
    }

    /// The standard share popover, anchored under the cursor.
    static func showSharePicker(for urls: [URL], model: IslandModel) {
        guard !urls.isEmpty,
              let view = NSApp.windows.first(where: { $0 is NotchPanel })?.contentView,
              let window = view.window else { return }
        let picker = NSSharingServicePicker(items: urls)
        picker.delegate = pickerDelegate
        pickerDelegate.onFinish = { model.isMenuOpen = false }
        self.picker = picker
        model.isMenuOpen = true
        let point = view.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        picker.show(relativeTo: NSRect(x: point.x - 1, y: point.y - 1, width: 2, height: 2), of: view, preferredEdge: .minY)
    }

    private final class PickerDelegate: NSObject, NSSharingServicePickerDelegate {
        var onFinish: (() -> Void)?

        func sharingServicePicker(_ picker: NSSharingServicePicker, didChoose service: NSSharingService?) {
            onFinish?()
        }
    }
}
