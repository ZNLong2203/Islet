import SwiftUI

struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let corner: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.45, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

/// Fake audio visualizer: bars bounce while playing, settle when paused.
///
/// The bounce is a repeating Core Animation, so the render server animates it and the app
/// does no per-frame work. That matters because this view is on screen whenever music plays.
struct WaveformView: NSViewRepresentable {
    let isPlaying: Bool
    let color: Color
    var bars = 4
    var maxHeight: CGFloat = 14

    func makeNSView(context: Context) -> WaveformBarsView {
        WaveformBarsView(bars: bars, maxHeight: maxHeight)
    }

    func updateNSView(_ view: WaveformBarsView, context: Context) {
        view.update(color: NSColor(color), playing: isPlaying)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: WaveformBarsView, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }
}

final class WaveformBarsView: NSView {
    private static let barWidth: CGFloat = 3
    private static let gap: CGFloat = 2
    private static let periods: [CFTimeInterval] = [0.43, 0.31, 0.52, 0.37, 0.47]

    private let bars: [CALayer]
    private let maxHeight: CGFloat
    private var isPlaying: Bool?
    private var color: NSColor?

    /// Vertical scale of a resting bar (a 3pt dot).
    private var restScale: CGFloat { Self.barWidth / maxHeight }

    init(bars count: Int, maxHeight: CGFloat) {
        self.maxHeight = maxHeight
        bars = (0..<count).map { _ in CALayer() }
        super.init(frame: .zero)
        wantsLayer = true
        for bar in bars {
            bar.cornerRadius = Self.barWidth / 2
            bar.transform = CATransform3DMakeScale(1, restScale, 1)
            layer?.addSublayer(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize {
        let count = CGFloat(bars.count)
        return NSSize(width: count * Self.barWidth + (count - 1) * Self.gap, height: maxHeight)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let originY = (bounds.height - maxHeight) / 2
        for (i, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: Self.barWidth, height: maxHeight)
            bar.position = CGPoint(x: CGFloat(i) * (Self.barWidth + Self.gap) + Self.barWidth / 2,
                                   y: originY + maxHeight / 2)
        }
        CATransaction.commit()
    }

    func update(color: NSColor, playing: Bool) {
        if color != self.color {
            self.color = color
            bars.forEach { $0.backgroundColor = color.cgColor }
        }
        guard playing != isPlaying else { return }
        isPlaying = playing
        for (i, bar) in bars.enumerated() {
            if playing {
                let bounce = CABasicAnimation(keyPath: "transform.scale.y")
                bounce.fromValue = 0.25
                bounce.toValue = 1.0
                bounce.duration = Self.periods[i % Self.periods.count]
                bounce.autoreverses = true
                bounce.repeatCount = .infinity
                bounce.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                bounce.timeOffset = Double(i) * 0.17
                bar.add(bounce, forKey: "bounce")
            } else {
                // Settle from wherever the bar currently is instead of snapping flat.
                let current = bar.presentation()?.value(forKeyPath: "transform.scale.y") as? CGFloat ?? restScale
                bar.removeAnimation(forKey: "bounce")
                let settle = CABasicAnimation(keyPath: "transform.scale.y")
                settle.fromValue = current
                settle.toValue = restScale
                settle.duration = 0.25
                bar.add(settle, forKey: "settle")
            }
        }
    }
}

struct ProgressRing: View {
    let progress: Double
    let color: Color
    var lineWidth: CGFloat = 6

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)
        }
    }
}

struct BatteryBadge: View {
    let level: Int
    let charging: Bool
    var tint: Color = .white

    var body: some View {
        HStack(spacing: 5) {
            Text("\(level)%")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(tint)
            BatteryGlyph(level: level, charging: charging)
        }
    }
}

struct BatteryGlyph: View {
    let level: Int
    let charging: Bool

    private var fill: Color {
        if charging { return .green }
        return level <= 20 ? .red : .white
    }

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .stroke(.white.opacity(0.45), lineWidth: 1)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(fill)
                    .frame(width: max(2, 18 * CGFloat(level) / 100))
                    .padding(2)
                if charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: 24, height: 12)
            Capsule().fill(.white.opacity(0.45)).frame(width: 1.5, height: 4)
        }
    }
}

/// Text that scrolls horizontally when it is too long for its box.
struct MarqueeText: View {
    let text: String
    var font: Font = .system(size: 14, weight: .semibold)
    var height: CGFloat = 18
    var speed: CGFloat = 28

    @ViewState private var textWidth: CGFloat = 0
    @ViewState private var boxWidth: CGFloat = 0

    var body: some View {
        Group {
            if textWidth > boxWidth {
                ScrollingTextView(text: text, font: font, speed: speed)
            } else {
                Text(text).font(font).lineLimit(1)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(height: height)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { boxWidth = $0 }
        .background(
            Text(text).font(font).fixedSize().hidden()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
        )
    }
}

/// The scrolling half of `MarqueeText`: the title is rendered to a bitmap once and slid by a
/// repeating Core Animation, so a long song title costs no CPU while the island is open.
private struct ScrollingTextView: NSViewRepresentable {
    let text: String
    let font: Font
    let speed: CGFloat

    func makeNSView(context: Context) -> ScrollingTextLayerView { ScrollingTextLayerView() }

    func updateNSView(_ view: ScrollingTextLayerView, context: Context) {
        view.show(text: text, font: font, speed: speed)
    }
}

final class ScrollingTextLayerView: NSView {
    private static let gap: CGFloat = 36
    private static let pause: CFTimeInterval = 2

    private let strip = CALayer()
    private let copies = [CALayer(), CALayer()]
    private let fade = CAGradientLayer()
    private var shownText: String?
    private var textSize: CGSize = .zero
    private var speed: CGFloat = 28

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        copies.forEach { strip.addSublayer($0) }
        layer?.addSublayer(strip)
        // Soft edges so letters slide in and out instead of being chopped.
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        fade.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        fade.locations = [0, 0.04, 0.9, 1]
        layer?.mask = fade
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show(text: String, font: Font, speed: CGFloat) {
        guard text != shownText else { return }
        shownText = text
        self.speed = speed
        let scale = window?.backingScaleFactor ?? 2
        let renderer = ImageRenderer(content: Text(text).font(font).foregroundStyle(.white).fixedSize())
        renderer.scale = scale
        guard let image = renderer.cgImage else { return }
        textSize = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        copies.forEach {
            $0.contents = image
            $0.contentsScale = scale
        }
        needsLayout = true
        restartScroll()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.frame = bounds
        let y = (bounds.height - textSize.height) / 2
        strip.frame = CGRect(x: 0, y: y, width: textSize.width * 2 + Self.gap, height: textSize.height)
        copies[0].frame = CGRect(origin: .zero, size: textSize)
        copies[1].frame = CGRect(origin: CGPoint(x: textSize.width + Self.gap, y: 0), size: textSize)
        CATransaction.commit()
    }

    private func restartScroll() {
        let distance = textSize.width + Self.gap
        let move = CABasicAnimation(keyPath: "transform.translation.x")
        move.fromValue = 0
        move.toValue = -distance
        move.beginTime = Self.pause
        move.duration = CFTimeInterval(distance / speed)
        // Rest at the start for `pause` seconds, slide one copy's width, then loop seamlessly.
        let loop = CAAnimationGroup()
        loop.animations = [move]
        loop.duration = Self.pause + move.duration
        loop.repeatCount = .infinity
        strip.removeAllAnimations()
        strip.add(loop, forKey: "marquee")
    }
}

struct IconButton: View {
    let symbol: String
    var size: CGFloat = 14
    var help: LocalizedStringKey = ""
    let action: () -> Void

    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: size + 16, height: size + 16)
                .background(Circle().fill(.white.opacity(hovering ? 0.14 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// The macOS 27 SDK turns `@State` into a macro whose plugin only ships with Xcode.
/// Spelling the property wrapper through an alias keeps Command Line Tools builds working.
typealias ViewState<Value> = SwiftUI.State<Value>
