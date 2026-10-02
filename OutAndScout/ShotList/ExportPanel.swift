import QuickLook
import SwiftUI
import UIKit

/// 03 Export panel. Slides in on the Shot List: this scene or all scenes,
/// then PDF for the crew, CSV for spreadsheets, or a view-only link.
struct ExportPanel: View {
    @Environment(ScoutStore.self) private var store
    /// The scene the Shot List is showing, or nil for all scenes.
    let scene: ScoutScene?

    @State private var allScenes = false
    @State private var format = Choice.pdf
    @State private var options = Exporter.Options()
    @State private var shareItem: ShareItem?
    @State private var error: String?
    /// A name typed over the default file name, without the extension.
    @State private var customName: String?
    /// The PDF being previewed in Quick Look.
    @State private var previewURL: URL?

    enum Choice: String, CaseIterable { case pdf, csv, link }

    var body: some View {
        let project = store.currentProject
        let thisScene = scene ?? store.currentScene
        let target = allScenes ? nil : thisScene
        let total = project.scenes.reduce(0) { $0 + $1.shots.count }
        let shots = target?.shots.count ?? total
        let ext = format == .csv ? "csv" : "pdf"
        let defaultName = Exporter.filename(project: project, scene: target, format: format == .csv ? .csv : .pdf)
            .replacingOccurrences(of: ".\(ext)", with: "")

        // v3c export panel: 380 wide, 18/20 padding, 12 between blocks, scrolls when it runs out of room.
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("export panel").font(.osDataSmall).foregroundStyle(Palette.graphite)
                        Text("export shot list").font(.osTitle)
                        Text("\(project.name) · \(target.map { "\($0.name) · " } ?? "all scenes · ")\(ShotListView.shots(shots))")
                            .font(.osData).foregroundStyle(Palette.graphite).lineLimit(1)
                    }

                    HStack(spacing: 6) {
                        scopeCard("this scene", "\(thisScene.name) · \(ShotListView.shots(thisScene.shots.count))", selected: !allScenes) { allScenes = false }
                        scopeCard("all scenes", "\(project.name) · \(ShotListView.shots(total))", selected: allScenes) { allScenes = true }
                    }

                    if allScenes && project.scenes.count > 1 {
                        SceneOrder(scenes: project.scenes) { store.moveScenes(from: $0, to: $1) }
                    }

                    VStack(spacing: 6) {
                        formatRow(.pdf, "pdf", "for the crew")
                        formatRow(.csv, "csv", "for spreadsheets")
                        // The live link needs outandscout.com/s/<project> to exist first.
                        formatRow(.link, "link", "view-only, live · soon")
                            .opacity(0.45)
                            .disabled(true)
                    }

                    HStack(spacing: 6) {
                        includeChip("frames", on: options.frames) { options.frames.toggle() }
                            .disabled(format == .csv)
                        includeChip("sun times", on: options.sunTimes) { options.sunTimes.toggle() }
                    }

                    Spacer(minLength: 0)

                    if let error {
                        Text(error).font(.osData).foregroundStyle(Palette.graphite)
                    }

                    Button { export(project: project, scene: target) } label: {
                        Text("\(target == nil ? "export all scenes" : "export scene") · \(ext)")
                            .font(.osTitle)
                            .foregroundStyle(Palette.paper)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Palette.ink, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    // Tap the file name to rename the export.
                    HStack(spacing: 0) {
                        EditableName(text: customName ?? defaultName, font: .osData, color: Palette.graphite, title: "file name") {
                            customName = Exporter.cleanName($0)
                        }
                        Text(".\(ext)").font(.osData).foregroundStyle(Palette.graphite)
                    }
                    .frame(maxWidth: .infinity)

                    if format == .pdf {
                        // Look before you send: opens the PDF in Quick Look.
                        Button("preview the pdf →") { preview(project: project, scene: target) }
                            .buttonStyle(.plain)
                            .font(.osData)
                            .underline()
                            .foregroundStyle(Palette.ink)
                            .frame(maxWidth: .infinity, minHeight: 28)
                    }
                }
                .padding(.vertical, 18)
                .padding(.horizontal, 20)
                .frame(minHeight: geo.size.height, alignment: .top)
            }
            .scrollIndicators(.hidden)
        }
        .frame(width: 380)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20, style: .continuous)
                .fill(Palette.paper)
                .ignoresSafeArea()
        )
        .foregroundStyle(Palette.ink)
        // The Shot List was showing every scene, so start there.
        .onAppear { allScenes = scene == nil }
        .quickLookPreview($previewURL)
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.url])
                .presentationDetents([.large])
        }
    }

    /// v3c scope card: 50 high, radius 12; picked = 2px ink on white, else a 1px rule.
    private func scopeCard(_ label: String, _ sub: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.osRow)
                Text(sub).font(.osDataSmall).foregroundStyle(Palette.graphite).lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 50)
            .modifier(Picked(selected: selected, radius: 12))
        }
        .buttonStyle(.plain)
    }

    /// v3c format row: 42 high, radius 12, label left and what it's for on the right.
    private func formatRow(_ choice: Choice, _ label: String, _ sub: String) -> some View {
        Button { format = choice } label: {
            HStack {
                Text(label).font(.osRow)
                Spacer()
                Text(sub).font(.osData).foregroundStyle(Palette.graphite)
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .modifier(Picked(selected: format == choice, radius: 12))
        }
        .buttonStyle(.plain)
    }

    /// v3c include chip: 32 high, ink when on, rule outline when off.
    private func includeChip(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.osData)
                .foregroundStyle(on ? Palette.paper : Palette.ink)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(on ? Palette.ink : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(on ? Palette.ink : Palette.rule, lineWidth: 1))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func preview(project: Project, scene: ScoutScene?) {
        previewURL = try? Exporter.export(project: project, scene: scene, format: .pdf, options: options, name: customName)
        if previewURL == nil { error = "Couldn't make the preview. Try again." }
    }

    private func export(project: Project, scene: ScoutScene?) {
        do {
            let url = try Exporter.export(project: project, scene: scene, format: format == .csv ? .csv : .pdf, options: options, name: customName)
            shareItem = ShareItem(url: url)
            error = nil
        } catch {
            self.error = "Couldn't make the file. Try again."
        }
    }
}

/// 2px ink border on white when picked, otherwise a 1px rule border on the paper.
private struct Picked: ViewModifier {
    let selected: Bool
    let radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(selected ? Color.white : .clear, in: shape)
            .overlay(shape.strokeBorder(selected ? Palette.ink : Palette.rule, lineWidth: selected ? 2 : 1))
            .contentShape(shape)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// "scene order · drag to reorder": rows 40 high with 4 between them; drag the grip
/// on the right and the row moves as you pass each neighbour, like the v3c board.
private struct SceneOrder: View {
    let scenes: [ScoutScene]
    let move: (IndexSet, Int) -> Void

    @State private var dragging: UUID?
    private let pitch: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("scene order")
                Spacer()
                Text("drag to reorder")
            }
            .font(.osDataSmall)
            .foregroundStyle(Palette.graphite)

            VStack(spacing: 4) {
                ForEach(Array(scenes.enumerated()), id: \.element.id) { i, s in
                    row(i, s)
                }
            }
            .coordinateSpace(name: "sceneOrder")
            .animation(.snappy(duration: 0.18), value: scenes.map(\.id))
        }
    }

    private func row(_ i: Int, _ s: ScoutScene) -> some View {
        let picked = dragging == s.id
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return HStack(spacing: 10) {
            Text(String(format: "%02d", i + 1))
                .font(.osDataSmall).foregroundStyle(Palette.graphite)
                .frame(width: 16, alignment: .leading)
            Text(s.name).font(.osRow).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(ShotListView.shots(s.shots.count)).font(.osDataSmall).foregroundStyle(Palette.graphite)
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13))
                .foregroundStyle(Palette.graphite)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named("sceneOrder"))
                        .onChanged { g in
                            if dragging == nil { dragging = s.id }
                            guard let from = scenes.firstIndex(where: { $0.id == s.id }) else { return }
                            let to = max(0, min(scenes.count - 1, Int(floor(g.location.y / pitch))))
                            if to != from {
                                move(IndexSet(integer: from), to > from ? to + 1 : to)
                            }
                        }
                        .onEnded { _ in dragging = nil }
                )
                .accessibilityLabel("drag to reorder \(s.name)")
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(height: 40)
        .background(picked ? Color.white : .clear, in: shape)
        .overlay(shape.strokeBorder(picked ? Palette.ink : Palette.rule, lineWidth: picked ? 2 : 1))
    }
}

struct ShareItem: Identifiable {
    let url: URL
    var id: URL { url }
}

/// The system share sheet: AirDrop, Mail, Files, Messages.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
