import SwiftUI
import UIKit

/// The size each Home grid cell asks for (set with `.layoutValue(key:value:)`).
struct HomeCardSizeKey: LayoutValueKey {
    static let defaultValue: CardSize = .large
}

/// True inside the "Add cards" previews: cards there draw from your data but must not start
/// anything (live heart rate stays off).
private struct HomeCardPreviewKey: EnvironmentKey {
    static let defaultValue = false
}

/// True while a card is drawn inside the frame that stretches under a resize drag: that frame
/// draws the card's background, so the card skips its own (two translucent layers would show).
private struct HomeCardBareKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var homeCardPreview: Bool {
        get { self[HomeCardPreviewKey.self] }
        set { self[HomeCardPreviewKey.self] = newValue }
    }

    var homeCardBare: Bool {
        get { self[HomeCardBareKey.self] }
        set { self[HomeCardBareKey.self] = newValue }
    }
}

/// Each card's frame on screen, reported while a card is being moved.
struct HomeCellFrameKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// The card being moved in edit mode (TodayView).
struct HomeMove: Equatable {
    let id: String
    /// Where the finger went down and where it is now, on screen.
    var start: CGPoint?
    var finger: CGPoint = .zero
    /// Where the finger holds the card, from its top-left corner.
    var grab: CGSize?
    /// The finger has moved since the lift, so `finger` is real.
    var tracking = false
    /// Let go: the card glides into its slot.
    var landing = false

    init(id: String) {
        self.id = id
    }
}

/// The card a moved card rests on, and where: its middle (to stack) or nearer an edge (to go
/// before or after it).
struct HomeZone: Equatable {
    let target: String
    let middle: Bool
    let after: Bool
}

/// A card being moved in edit mode: lifted after a short hold, then following the finger.
enum HomeDragEvent {
    case lifted
    /// Screen coordinates: where the finger went down and where it is now.
    case moved(start: CGPoint, location: CGPoint)
    case ended
}

/// Lays Home cards out like iOS widgets: a small card takes half the width and sits next to the
/// small card after it, medium and large cards take the whole width. The order is kept, so a
/// small card followed by a wide one leaves the other half empty. One flat layout (rather than
/// rows of stacks) keeps every card's identity when its size changes, so a resize drag keeps
/// going while the card grows or shrinks under the finger.
struct HomeGridLayout: Layout {
    var columnSpacing: CGFloat = 12
    var rowSpacing: CGFloat = 14

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 360
        let frames = arrange(width: width, subviews: subviews)
        return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrange(width: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let f = frames[index]
            subview.place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY),
                          anchor: .topLeading,
                          proposal: ProposedViewSize(width: f.width, height: f.height))
        }
    }

    /// Frames relative to the top-left corner. A cell that draws nothing (height 0) takes no
    /// space and adds no spacing.
    private func arrange(width: CGFloat, subviews: Subviews) -> [CGRect] {
        let half = max(0, (width - columnSpacing) / 2)
        var frames = Array(repeating: CGRect.zero, count: subviews.count)
        var y: CGFloat = 0
        // Height of the small card waiting on the left for a partner.
        var leftHeight: CGFloat?
        for (index, subview) in subviews.enumerated() {
            if subview[HomeCardSizeKey.self] == .small {
                let h = subview.sizeThatFits(ProposedViewSize(width: half, height: nil)).height
                guard h > 0 else {
                    frames[index] = CGRect(x: 0, y: y, width: half, height: 0)
                    continue
                }
                if let left = leftHeight {
                    frames[index] = CGRect(x: half + columnSpacing, y: y, width: half, height: h)
                    y += max(left, h) + rowSpacing
                    leftHeight = nil
                } else {
                    frames[index] = CGRect(x: 0, y: y, width: half, height: h)
                    leftHeight = h
                }
            } else {
                if let left = leftHeight {
                    y += left + rowSpacing
                    leftHeight = nil
                }
                let h = subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
                frames[index] = CGRect(x: 0, y: y, width: width, height: h)
                if h > 0 { y += h + rowSpacing }
            }
        }
        return frames
    }
}

/// A slight, endless wobble while Home is being edited, like the iOS Home Screen. It pauses
/// while `active` is false (a card being resized holds still) and is off with Reduce Motion.
struct Jiggle: ViewModifier {
    let amplitude: Double
    let seed: Int
    var active = true
    @State private var tilted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(reduceMotion || !active ? 0 : (tilted ? amplitude : -amplitude)))
            .onAppear { start() }
            .onChange(of: active) { _, on in
                if on { start() }
            }
    }

    private func start() {
        guard !reduceMotion, active else { return }
        tilted = false
        withAnimation(.easeInOut(duration: 0.13 + Double(seed % 4) * 0.015).repeatForever(autoreverses: true)) {
            tilted = true
        }
    }
}

/// A Home card in edit mode: it wobbles, can't be tapped through, has a remove button on its
/// top-left corner and a resize handle on its bottom corner (the left one for the right card of
/// a small pair, so it can grow into the row). Tapping it opens its settings. Holding it for a
/// moment lifts it, and it then follows the finger (TodayView moves the others out of the way,
/// or stacks it on the card whose middle it rests on).
///
/// Resizing works like iOS widgets: the whole card stretches under the finger dragging the
/// handle, between the small and the large footprint, drawn at the size it will take while the
/// cards around it make room, and it settles into that size when the finger lifts. TodayView
/// draws the stretched card (HomeStretchedCard) above everything, so it stays under the finger
/// when its slot moves to another row.
struct HomeEditCell<Content: View>: View {
    let item: HomeItem
    let seed: Int
    let canRemove: Bool
    /// The right card of a pair of small ones.
    let inRightColumn: Bool
    /// This card is the one being moved: its slot shows as an empty outline.
    let isMoving: Bool
    /// This card is being resized: TodayView draws it stretched, so its slot stays empty.
    let isResizing: Bool
    /// A moved card rests on this one's middle: letting go makes a stack.
    let isStackTarget: Bool
    var onRemove: () -> Void
    var onResize: (CardSize) -> Void
    var onMove: (Int) -> Void
    var onEdit: () -> Void
    /// The stretched card while the handle is dragged; nil once it's let go.
    var onResizing: (HomeResize?) -> Void
    var onDrag: (HomeDragEvent) -> Void
    /// The card at a size.
    @ViewBuilder var content: (CardSize) -> Content

    /// The card's frame on screen when the resize began, and the bounds it can stretch to.
    private struct ResizeBase {
        let start: CGRect
        let fullWidth: CGFloat
        let largeHeight: CGFloat
        let leftward: Bool
    }

    /// The handle is being dragged; the card's frame on screen comes with the next layout.
    @State private var resizeStarted = false
    @State private var resizeBase: ResizeBase?
    @State private var resizeTranslation: CGSize = .zero
    @GestureState private var resizeGesture: CGSize? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    /// A small or medium card's height at the current text size.
    private var glanceHeight: CGFloat { HomeGlanceMetrics.height(for: typeSize) }

    // Computed: a generic type can't have static stored properties. Same as HomeGridLayout.
    private static var columnSpacing: CGFloat { 12 }
    private static var rowSpacing: CGFloat { 14 }

    var body: some View {
        content(item.size)
            .allowsHitTesting(false)
            .opacity(isMoving || isResizing ? 0 : 1)
            // Takes the touches the card lets through: a tap opens its settings, a short hold
            // lifts it. Behind the card, so VoiceOver still finds the card's own content.
            .background {
                HomeCardTouches(onTap: onEdit, onDrag: onDrag)
            }
            .overlay {
                if isMoving { movingSlot }
            }
            .overlay(alignment: .topLeading) {
                if canRemove && !isResizing && !isMoving { removeButton }
            }
            // Always in the view tree while resizing: removing it would cancel the drag it carries.
            .overlay(alignment: handleLeading ? .bottomLeading : .bottomTrailing) {
                if !isMoving { resizeHandle }
            }
            .overlay {
                if isStackTarget { stackHighlight }
            }
            .scaleEffect(isStackTarget ? 1.04 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isStackTarget)
            .modifier(Jiggle(amplitude: amplitude, seed: seed,
                             active: !resizeStarted && !isResizing && !isStackTarget && !isMoving))
            // Outside the wobble, so the frame on screen is the slot's, not a tilted one.
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onChange(of: resizeStarted) { _, started in
                            if started { beginResize(at: geo.frame(in: .global)) }
                        }
                }
            }
            .sensoryFeedback(.selection, trigger: item.size)
            .sensoryFeedback(.impact(weight: .light), trigger: isStackTarget)
            .onChange(of: resizeGesture) { _, now in
                // A cancelled drag never calls onEnded.
                if now == nil { endResize() }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("\(item.title), \(item.size.label)"))
            .accessibilityHint(Text(item.card.hasSettings ? "Tap for its settings" : ""))
            .accessibilityActions {
                ForEach(item.card.sizes.filter { $0 != item.size }) { size in
                    Button("Make \(size.label.lowercased())") { onResize(size) }
                }
                if item.card.hasSettings { Button("Settings") { onEdit() } }
                Button("Move up") { onMove(-1) }
                Button("Move down") { onMove(1) }
                if canRemove { Button("Remove") { onRemove() } }
            }
    }

    /// Bigger cards wobble less, so their far edges don't swing too much.
    private var amplitude: Double {
        switch item.size {
        case .small: return 1.4
        case .medium: return 0.8
        case .large: return 0.45
        }
    }

    // MARK: moving

    private var movingSlot: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(Color.white.opacity(0.28), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            .allowsHitTesting(false)
    }

    private var stackHighlight: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(Color.white, lineWidth: 3)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.08)))
            .overlay {
                Label("Release to stack", systemImage: HomeCard.stack.icon)
                    .font(Font.fs(.subheadline, .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.white))
            }
            .allowsHitTesting(false)
    }

    // MARK: resizing

    /// The handle's corner, kept while a resize is going even if the card changes column.
    private var handleLeading: Bool {
        resizeBase?.leftward ?? (item.size == .small && inRightColumn)
    }

    private func resizeChanged(_ t: CGSize) {
        resizeTranslation = t
        guard let base = resizeBase else {
            // The frame on screen arrives with the next layout (beginResize).
            if !resizeStarted { resizeStarted = true }
            return
        }
        report(base)
    }

    private func beginResize(at frame: CGRect) {
        guard resizeStarted, resizeBase == nil else { return }
        let twoRows = 2 * glanceHeight + Self.rowSpacing
        let base = ResizeBase(start: frame,
                              fullWidth: item.size == .small ? frame.width * 2 + Self.columnSpacing : frame.width,
                              largeHeight: item.size == .large ? max(twoRows, frame.height) : twoRows,
                              leftward: item.size == .small && inRightColumn)
        resizeBase = base
        report(base)
    }

    private func report(_ base: ResizeBase) {
        let rect = stretchedRect(base, resizeTranslation)
        onResizing(HomeResize(id: item.id, rect: rect, leftward: base.leftward))
        let size = target(base, rect.size)
        if size != item.size { onResize(size) }
    }

    /// Lets go: TodayView glides the stretched card into the slot of its new size.
    private func endResize() {
        guard resizeStarted, !HomeLayout.holdsResize else { return }
        resizeStarted = false
        let began = resizeBase != nil
        resizeBase = nil
        if began { onResizing(nil) }
    }

    /// The stretched card on screen: its top edge stays, the handle's corner follows the finger.
    private func stretchedRect(_ base: ResizeBase, _ t: CGSize) -> CGRect {
        let smallWidth = max(0, (base.fullWidth - Self.columnSpacing) / 2)
        let w = min(max(base.start.width + (base.leftward ? -t.width : t.width), smallWidth), base.fullWidth)
        let maxH = item.card.sizes.contains(.large) ? base.largeHeight : glanceHeight
        let h = min(max(base.start.height + t.height, min(glanceHeight, base.start.height)), maxH)
        return CGRect(x: base.leftward ? base.start.maxX - w : base.start.minX, y: base.start.minY, width: w, height: h)
    }

    /// Past halfway between two footprints the card takes the bigger one. A one-column card
    /// can't be tall, so narrow means small.
    private func target(_ base: ResizeBase, _ live: CGSize) -> CardSize {
        let smallWidth = max(0, (base.fullWidth - Self.columnSpacing) / 2)
        let wide = live.width > (smallWidth + base.fullWidth) / 2
        let tall = live.height > (glanceHeight + base.largeHeight) / 2
        let size: CardSize = !wide ? .small : (tall ? .large : .medium)
        return item.card.sizes.contains(size) ? size : .medium
    }

    // MARK: corner controls

    private var removeButton: some View {
        Button(action: onRemove) {
            Image(systemName: "minus")
                .font(Font.fredoka(12, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color(white: 0.32)))
                .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: -16, y: -16)
        .accessibilityLabel(Text("Remove \(item.title)"))
        .accessibilityIdentifier("home-remove-\(item.id)")
    }

    /// While resizing, the stretched card shows the handle under the finger; this one only
    /// carries the drag.
    private var resizeHandle: some View {
        HomeResizeDot(leftward: handleLeading)
            .opacity(isResizing ? 0 : 1)
            .contentShape(Rectangle())
            .offset(x: handleLeading ? -10 : 10, y: 10)
            .highPriorityGesture(
                // Global space, so the wobble's rotation doesn't shake the card.
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .updating($resizeGesture) { value, state, _ in state = value.translation }
                    .onChanged { value in resizeChanged(value.translation) }
                    .onEnded { _ in endResize() }
            )
            .onTapGesture { onResize(nextSize) }
            .accessibilityLabel(Text("Resize \(item.title)"))
            .accessibilityValue(Text(item.size.label))
            .accessibilityHint(Text("Drag to resize, or tap for the next size"))
            .accessibilityIdentifier("home-resize-\(item.id)")
    }

    private var nextSize: CardSize {
        let sizes = item.card.sizes
        guard let i = sizes.firstIndex(of: item.size) else { return item.card.defaultSize }
        return sizes[(i + 1) % sizes.count]
    }
}

/// The touches over a card in edit mode, in UIKit so the page still scrolls under them (a
/// SwiftUI hold-then-drag gesture over every card kept the page from scrolling): a tap opens the
/// card's settings, and holding still for a moment lifts the card, which then follows the
/// finger. A swipe that starts moving before that scrolls the page as usual.
struct HomeCardTouches: UIViewRepresentable {
    var onTap: () -> Void
    var onDrag: (HomeDragEvent) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.accessibilityElementsHidden = true
        let hold = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.hold(_:)))
        hold.minimumPressDuration = 0.2
        hold.allowableMovement = 10
        view.addGestureRecognizer(hold)
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:))))
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject {
        var parent: HomeCardTouches
        /// Where the hold began, in window coordinates (SwiftUI's global space).
        private var start: CGPoint = .zero

        init(_ parent: HomeCardTouches) {
            self.parent = parent
        }

        @objc func tap(_ gesture: UITapGestureRecognizer) {
            if gesture.state == .ended { parent.onTap() }
        }

        @objc func hold(_ gesture: UILongPressGestureRecognizer) {
            let p = gesture.location(in: nil)
            switch gesture.state {
            case .began:
                start = p
                parent.onDrag(.lifted)
                // Lifted at once, under the finger, before it moves.
                parent.onDrag(.moved(start: p, location: p))
            case .changed:
                parent.onDrag(.moved(start: start, location: p))
            case .ended, .cancelled, .failed:
                parent.onDrag(.ended)
            default:
                break
            }
        }
    }
}

/// A card being resized in edit mode (TodayView): the stretched card's frame on screen.
struct HomeResize: Equatable {
    let id: String
    var rect: CGRect
    /// The right card of a small pair grows to the left, from its bottom-left corner.
    let leftward: Bool
    /// Let go: the card glides into its new slot.
    var settling = false
}

/// The round resize handle on an edited card's bottom corner.
struct HomeResizeDot: View {
    var leftward = false

    var body: some View {
        Image(systemName: leftward ? "arrow.up.right.and.arrow.down.left" : "arrow.up.left.and.arrow.down.right")
            .font(Font.fredoka(11, weight: .bold))
            .foregroundStyle(.black)
            .frame(width: 26, height: 26)
            .background(Circle().fill(.white))
            .shadow(color: .black.opacity(0.35), radius: 3)
            .frame(width: 44, height: 44)
    }
}

/// A card stretched by a resize drag, like an iOS widget: the whole card follows the finger,
/// its content laid out at the size it will take (cut off or with room below while the stretch
/// is between sizes).
struct HomeStretchedCard<Content: View>: View {
    let size: CGSize
    let leftward: Bool
    let settling: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        content()
            .frame(width: size.width, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.homeCardBare, true)
            .environment(\.homeCardPreview, true)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            // Opaque, so the cards it passes over don't show through.
            .background(shape.fill(Theme.card).background(shape.fill(Theme.background)))
            .clipShape(shape)
            .overlay(shape.stroke(Theme.cardBorder, lineWidth: 1))
            .overlay(alignment: leftward ? .bottomLeading : .bottomTrailing) {
                HomeResizeDot(leftward: leftward)
                    .offset(x: leftward ? -10 : 10, y: 10)
                    .opacity(settling ? 0 : 1)
            }
            .scaleEffect(settling ? 1 : 1.02)
            .shadow(color: .black.opacity(settling ? 0 : 0.45), radius: 14, y: 6)
            .allowsHitTesting(false)
    }
}

/// A card that can't draw on this day (a today-only card on a past day, or one that needs the
/// day's data before it has synced), shown only while editing so it can still be moved,
/// resized or removed.
struct HomeCardPlaceholder: View {
    let card: HomeCard
    let title: String
    let size: CardSize
    let reason: String
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: card.icon)
                .font(Font.fs(.title3))
                .foregroundStyle(Theme.tertiary)
            Text(title)
                .font(Font.fs(.subheadline, .semibold))
                .foregroundStyle(Theme.secondary)
                .lineLimit(2)
            Text(reason)
                .font(Font.fs(.caption))
                .foregroundStyle(Theme.tertiary)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: size == .large ? 2 * HomeGlanceMetrics.height(for: typeSize) + 14 : HomeGlanceMetrics.height(for: typeSize))
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.cardBorder, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        )
    }
}
