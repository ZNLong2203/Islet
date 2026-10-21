import SwiftUI

struct ExpandedView: View {
    let model: IslandModel

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: model.notchSize.height)
            Group {
                switch model.tab {
                case .home: HomeTab(model: model)
                case .notes: NotesTab(model: model)
                case .shelf: ShelfTab(model: model)
                case .timer: TimerTab(timer: model.timer)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .padding(.horizontal, Metrics.expandedTopRadius)
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(ExpandedTab.allCases) { tab in
                    TabButton(tab: tab, isSelected: model.tab == tab) { model.tab = tab }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear.frame(width: model.notchSize.width + 16)

            HStack(spacing: 8) {
                if model.battery.hasBattery {
                    BatteryBadge(level: model.battery.level, charging: model.battery.isCharging)
                }
                IconButton(symbol: "gearshape.fill", size: 12, help: "Settings") {
                    model.onOpenSettings?()
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.top, 2)
    }
}

private struct TabButton: View {
    let tab: ExpandedTab
    let isSelected: Bool
    let action: () -> Void

    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: tab.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.5))
                .frame(width: 30, height: 22)
                .background(Capsule().fill(.white.opacity(isSelected ? 0.16 : (hovering ? 0.08 : 0))))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
