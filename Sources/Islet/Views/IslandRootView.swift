import SwiftUI

struct IslandRootView: View {
    let model: IslandModel

    private let spring = Animation.spring(response: 0.42, dampingFraction: 0.78)

    var body: some View {
        let presentation = model.presentation
        let shape = NotchShape(topRadius: model.topRadius, bottomRadius: model.bottomRadius)

        let expanded = presentation == .expanded

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // The shadow hangs off the plain black shape, not the content, so scrolling text
                // or a ticking timer doesn't force the blur to be recomputed every frame.
                shape.fill(Color.black)
                    .shadow(color: .black.opacity(0.55), radius: expanded ? 18 : 0, y: expanded ? 8 : 0)
                content(for: presentation)
                    .frame(width: model.islandSize.width, height: model.islandSize.height, alignment: .top)
                    .clipShape(shape)
            }
            .frame(width: model.islandSize.width, height: model.islandSize.height)
            .onDrop(of: [.fileURL], isTargeted: Binding(
                get: { model.isDropTargeted },
                set: { model.isDropTargeted = $0; if $0 { model.tab = .shelf } }
            )) { providers in
                model.shelf.handleDrop(providers)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .animation(spring, value: presentation)
        .animation(spring, value: model.islandSize)
        .animation(spring, value: model.tab)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func content(for presentation: Presentation) -> some View {
        switch presentation {
        case .idle:
            EmptyView()
        case .wings:
            CompactWingsView(model: model).transition(.island)
        case .peek(let kind):
            PeekView(kind: kind, model: model).transition(.island)
        case .expanded:
            ExpandedView(model: model).transition(.island)
        }
    }
}

private struct BlurModifier: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View { content.blur(radius: radius) }
}

extension AnyTransition {
    /// Content melts in and out of the black like on the iPhone.
    static var island: AnyTransition {
        AnyTransition.modifier(active: BlurModifier(radius: 10), identity: BlurModifier(radius: 0))
            .combined(with: .opacity)
            .combined(with: .scale(scale: 0.88, anchor: .top))
    }
}

/// Lays content out on both sides of the camera housing.
struct WingsLayout<Leading: View, Trailing: View>: View {
    let notchWidth: CGFloat
    let height: CGFloat
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 0) {
            leading.frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: notchWidth)
            trailing.frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, Metrics.compactTopRadius + 8)
        .frame(height: height)
    }
}
