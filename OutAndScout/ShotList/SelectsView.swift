import SwiftUI
import UIKit

/// Selects (18 Nov 2026): for jobs where only the stills go out, no PDF. Every still as a
/// grid, picked the way Photos does it (tap to tick, drag sideways across a run, hold to
/// look full screen), then "Send 7" makes plain JPEGs cropped to their frame lines and
/// opens the share sheet: AirDrop, WhatsApp, Mail, Save to Photos, Files.
struct SelectsView: View {
    @Environment(ScoutStore.self) private var store
    @Environment(\.isPortrait) private var portrait
    /// The scene the Shot List was showing, or nil for all scenes.
    let scene: ScoutScene?
    let onClose: () -> Void

    @State private var allScenes = false
    @State private var picked: Set<UUID> = []
    /// While dragging: whether the drag ticks or unticks, and what was picked before it.
    @State private var dragTicks: Bool?
    @State private var beforeDrag: Set<UUID> = []
    @State private var dragStart: Int?
    @State private var making: (done: Int, total: Int)?
    @State private var files: [URL]?
    @State private var peek: Shot?
    @State private var error: String?
    @State private var makeTask: Task<Void, Never>?

    private struct Item: Identifiable {
        let scene: ScoutScene
        let shot: Shot
        var id: UUID { shot.id }
    }

    private var project: Project { store.currentProject }
    private var thisScene: ScoutScene { scene ?? store.currentScene }
    private var items: [Item] {
        let scenes = allScenes ? project.scenes : [thisScene]
        return scenes.flatMap { sc in sc.shots.filter { $0.photoFile != nil }.map { Item(scene: sc, shot: $0) } }
    }
    private var pickedItems: [Item] { items.filter { picked.contains($0.id) } }

    private let gap: CGFloat = 3

    var body: some View {
        ZStack {
            Sheet.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 10) {
                header
                scopeRow
                GeometryReader { geo in
                    let cols = max(3, Int((geo.size.width + gap) / (portrait ? 118 : 128)))
                    let side = (geo.size.width - gap * CGFloat(cols - 1)) / CGFloat(cols)
                    ScrollView {
                        grid(cols: cols, side: side)
                            .padding(.bottom, 12)
                    }
                    .scrollIndicators(.hidden)
                }
                footer
            }
            .padding(.horizontal, portrait ? Space.m : Space.l)
            .padding(.top, 4)
            .foregroundStyle(Sheet.text)
            .disabled(making != nil)

            if let making { progressCard(making) }

            if let peek {
                ShotViewer(shots: items.map(\.shot), start: peek.id) { self.peek = nil }
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .animation(.easeOut(duration: 0.2), value: peek?.id)
        .onAppear { allScenes = scene == nil }
        .sheet(isPresented: Binding(get: { files != nil }, set: { if !$0 { files = nil } })) {
            ActivityView(items: files ?? []) { completed in
                if completed {
                    store.toast = "Sent \(picked.count == 1 ? "1 still" : "\(picked.count) stills")"
                    picked = []
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 8) {
            Text(picked.isEmpty ? "Select stills" : "\(picked.count) selected")
                .font(.osSans(18))
                .contentTransition(.numericText())
            Spacer()
            // Turn the phone upright to see more stills at once, like Photos (Elliot, 18 Nov).
            RotateButton(portrait: portrait)
            OPill(label: "Cancel", caps: true) { close() }
        }
        .frame(minHeight: 44)
    }

    private var scopeRow: some View {
        HStack(spacing: 6) {
            OPill(label: "This scene", on: !allScenes, size: .small) { allScenes = false; trimPicked() }
            OPill(label: "All scenes", on: allScenes, size: .small) { allScenes = true }
            Spacer()
            let all = !items.isEmpty && items.allSatisfy { picked.contains($0.id) }
            OPill(label: all ? "None" : "All", size: .small) {
                picked = all ? [] : Set(items.map(\.id))
            }
            .disabled(items.isEmpty)
        }
    }

    @ViewBuilder
    private func grid(cols: Int, side: CGFloat) -> some View {
        if items.isEmpty {
            Text("No stills in \(allScenes ? "this project" : "this scene") yet.")
                .font(.osData).foregroundStyle(Sheet.muted)
                .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(side), spacing: gap), count: cols), spacing: gap) {
                ForEach(items) { item in
                    cell(item, side: side)
                }
            }
            .coordinateSpace(name: "selects")
            // Drag sideways across stills to tick (or untick) a run, like Photos. A UIKit pan
            // that only begins on a sideways start, so an up-down flick goes straight to the
            // scroll view instead of fighting a SwiftUI drag.
            .gesture(SidewaysPan(
                changed: { start, now in dragChanged(start: start, now: now, cols: cols, side: side) },
                ended: { dragTicks = nil; dragStart = nil }
            ))
        }
    }

    private func cell(_ item: Item, side: CGFloat) -> some View {
        let on = picked.contains(item.id)
        return StillImage(shot: item.shot)
            .frame(width: side, height: side)
            .clipped()
            .overlay { if on { Color.white.opacity(0.18) } }
            .overlay(alignment: .topLeading) {
                Text(allScenes ? "\(item.scene.name.prefix(10)) · \(item.shot.number)" : item.shot.number)
                    .font(Fonts.mono(9))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.7), radius: 2)
                    .padding(5)
            }
            .overlay(alignment: .bottomTrailing) {
                ZStack {
                    Circle().fill(on ? Palette.sun : Color.black.opacity(0.25))
                    Circle().strokeBorder(on ? Palette.sun : .white, lineWidth: 1.5)
                    if on {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(hex: 0x111111))
                    }
                }
                .frame(width: 20, height: 20)
                .padding(5)
            }
            .contentShape(Rectangle())
            .onTapGesture { toggle(item.id) }
            // A long press that doesn't hold up the scroll view (it only claims the touch at 0.45 s).
            .gesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in peek = item.shot })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Shot \(item.shot.number), \(item.shot.caption)")
            .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let error {
                Text(error).font(.osDataSmall).foregroundStyle(Sheet.muted)
            } else {
                Text(picked.isEmpty ? "TAP OR DRAG TO PICK" : "\(picked.count) JPEG\(picked.count == 1 ? "" : "S") · ABOUT \(max(1, picked.count * 4)) MB")
                    .font(Fonts.mono(9)).tracking(0.6).foregroundStyle(Sheet.muted)
            }
            Spacer()
            OPill(label: picked.isEmpty ? "Send" : "Send \(picked.count)", on: !picked.isEmpty, size: .big, caps: true) { send() }
                .disabled(picked.isEmpty)
        }
        .padding(.vertical, 6)
        .overlay(alignment: .top) { Rectangle().fill(Sheet.rule).frame(height: 1) }
    }

    private func progressCard(_ p: (done: Int, total: Int)) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MAKING \(min(p.done + 1, p.total)) OF \(p.total)").font(Fonts.mono(10)).tracking(0.6)
            ProgressView(value: Double(p.done), total: Double(max(p.total, 1)))
                .tint(Palette.sun)
            HStack {
                Text("CROPPED TO FRAME LINES, FULL SIZE").font(Fonts.mono(9)).tracking(0.6).foregroundStyle(Sheet.muted)
                Spacer()
                OPill(label: "Stop", size: .small, caps: true) { makeTask?.cancel() }
            }
        }
        .padding(14)
        .frame(maxWidth: 320)
        .background(RoundedRectangle(cornerRadius: 14).fill(Outline.card))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Outline.line, lineWidth: 1.5))
        .foregroundStyle(Sheet.text)
        .padding(Space.m)
    }

    // MARK: Actions

    private func toggle(_ id: UUID) {
        if picked.contains(id) { picked.remove(id) } else { picked.insert(id) }
        error = nil
    }

    /// Going back to one scene drops picks from the others, so the count stays honest.
    private func trimPicked() {
        let ids = Set(thisScene.shots.map(\.id))
        picked = picked.intersection(ids)
    }

    private func index(at p: CGPoint, cols: Int, side: CGFloat) -> Int? {
        let col = Int(p.x / (side + gap)), row = Int(p.y / (side + gap))
        guard p.x >= 0, p.y >= 0, col < cols else { return nil }
        let i = row * cols + col
        return items.indices.contains(i) ? i : nil
    }

    private func dragChanged(start startPoint: CGPoint, now nowPoint: CGPoint, cols: Int, side: CGFloat) {
        if dragTicks == nil {
            // SidewaysPan only begins on a sideways start, so this is always a select run.
            guard let start = index(at: startPoint, cols: cols, side: side) else { return }
            dragStart = start
            beforeDrag = picked
            dragTicks = !picked.contains(items[start].id)
        }
        guard let ticks = dragTicks, let start = dragStart,
              let now = index(at: nowPoint, cols: cols, side: side) else { return }
        let run = Set(items[min(start, now)...max(start, now)].map(\.id))
        picked = ticks ? beforeDrag.union(run) : beforeDrag.subtracting(run)
    }

    private func send() {
        let chosen = pickedItems
        guard !chosen.isEmpty else { return }
        error = nil
        making = (0, chosen.count)
        // Names like rooftop-east_1A.jpg; a repeat gets _2, _3.
        var seen: [String: Int] = [:]
        let names: [UUID: String] = Dictionary(uniqueKeysWithValues: chosen.map { item in
            var base = "\(Format.slug(item.scene.name))_\(Format.slug(item.shot.number).uppercased())"
            if base.hasPrefix("_") { base = Format.slug(project.name) + base }
            let n = (seen[base] ?? 0) + 1
            seen[base] = n
            return (item.id, n == 1 ? base : "\(base)_\(n)")
        })
        let shots = chosen.map(\.shot)
        makeTask = Task {
            let folder = StillWriter.freshFolder("selects")
            let made = await StillWriter.writeAll(shots, into: folder,
                                                  names: { shot, _ in names[shot.id] ?? shot.id.uuidString },
                                                  progress: { done in making = (done, shots.count) })
            making = nil
            if Task.isCancelled { return }
            if made.isEmpty { error = "Couldn't read those stills." } else { files = made }
        }
    }

    private func close() {
        makeTask?.cancel()
        onClose()
    }
}

/// A pan that begins only when the finger starts sideways (|vx| > 1.2 |vy|), reporting the
/// start and current points in the grid's own coordinates. Anything else never begins, so the
/// enclosing ScrollView scrolls as normal.
private struct SidewaysPan: UIGestureRecognizerRepresentable {
    let changed: (CGPoint, CGPoint) -> Void
    let ended: () -> Void

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var start: CGPoint = .zero
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let pan = g as? UIPanGestureRecognizer else { return false }
            let v = pan.velocity(in: pan.view)
            return abs(v.x) > abs(v.y) * 1.2
        }
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { false }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        pan.maximumNumberOfTouches = 1
        return pan
    }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        let here = context.converter.localLocation
        switch pan.state {
        case .began:
            // Where the finger first went down: back out the distance already travelled.
            let t = context.converter.localTranslation ?? .zero
            context.coordinator.start = CGPoint(x: here.x - t.x, y: here.y - t.y)
            changed(context.coordinator.start, here)
        case .changed:
            changed(context.coordinator.start, here)
        case .ended, .cancelled, .failed:
            ended()
        default: break
        }
    }
}
