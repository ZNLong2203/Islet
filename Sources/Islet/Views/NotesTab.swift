import SwiftUI

struct NotesTab: View {
    let model: IslandModel

    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var notes = model.notes
        HStack(spacing: 12) {
            ZStack(alignment: .topLeading) {
                if notes.text.isEmpty {
                    Text("Jot something down…\nPress ⌃⌥N anywhere to open, Esc to close.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.horizontal, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $notes.text)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.never)
                    .focused($focused)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.yellow.opacity(focused ? 0.5 : 0), lineWidth: 1))

            VStack(spacing: 6) {
                IconButton(symbol: "doc.on.doc", size: 13, help: "Copy") { notes.copyAll() }
                IconButton(symbol: "trash", size: 13, help: "Clear all") { notes.clear() }
                Spacer()
                Text("\(notes.text.count)")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .onChange(of: model.notesFocusRequest, initial: true) { focused = model.notesFocusRequest > 0 }
    }
}
