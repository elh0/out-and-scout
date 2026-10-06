import QuickLook
import SwiftUI
import UIKit

/// 03 Export panel. Slides in on the Shot List: this scene or all scenes,
/// then PDF for the crew, CSV for spreadsheets, or a view-only link.
struct ExportPanel: View {
    @Environment(ScoutStore.self) private var store
    @Environment(\.isPortrait) private var portrait
    /// The scene the Shot List is showing, or nil for all scenes.
    let scene: ScoutScene?

    @State private var allScenes = false
    /// The rename / reorder list, folded away until asked for.
    @State private var format = Choice.pdf
    @State private var options = Exporter.Options()
    @State private var shareItem: ShareItem?
    @State private var error: String?
    /// A name typed over the default file name, without the extension.
    @State private var customName: String?
    /// The PDF being previewed in Quick Look.
    @State private var previewURL: URL?
    /// A PDF is being made; building one with stills can take a moment on older phones.
    @State private var busy = false

    enum Choice: String, CaseIterable { case pdf, csv, photos, link }

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
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Done is always here, so the panel can be closed however little room is left
                    // around it (upright it fills the screen).
                    PanelHeader(
                        title: "Export",
                        sub: "\(project.name) · \(target.map { "\($0.name) · " } ?? "All scenes · ")\(ShotListView.shots(shots))",
                        action: ("Done", { store.showingExport = false })
                    )

                    // Which scenes first, as two big halves, since it's half of every export
                    // (Elliot, 6 Oct 2026: it was hidden down the scroll). Then what to send.
                    HStack(spacing: 0) {
                        scopeHalf("This scene", "\(thisScene.name) · \(ShotListView.shots(thisScene.shots.count))", on: !allScenes) { allScenes = false }
                        scopeHalf("All scenes", "\(project.scenes.count) · \(ShotListView.shots(total))", on: allScenes) { allScenes = true }
                    }
                    .overlay(Rectangle().strokeBorder(Sheet.text, lineWidth: 1))

                    // What to send: six tiles, two across, so every choice is on screen at once.
                    VStack(alignment: .leading, spacing: 6) {
                        Caps(text: "What to send").foregroundStyle(Sheet.muted)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                            ForEach(Exporter.Tier.allCases, id: \.self) { t in
                                tile(selected: format == .pdf && options.tier == t, t.label, "PDF", tierShort(t)) {
                                    format = .pdf
                                    options.tier = t
                                }
                            }
                            tile(selected: format == .csv, "Spreadsheet", "CSV", "For the AD") { format = .csv }
                            tile(selected: format == .photos, "Camera roll", nil, "Stills to Photos") { format = .photos }
                            // The live link needs outandscout.com/s/<project> to exist first.
                            tile(selected: false, "Live link", nil, "Soon") {}
                                .opacity(0.45)
                                .disabled(true)
                        }
                    }

                    if format == .csv || (format == .pdf && options.tier == .summary) {
                        HStack(spacing: Space.l) {
                            includeChip("Frames", on: options.frames) { options.frames.toggle() }
                                .disabled(format == .csv)
                            includeChip("Sun Times", on: options.sunTimes) { options.sunTimes.toggle() }
                        }
                    }
                }
                .padding(.top, 18)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            // Long scene lists stop at the footer instead of running under the button.
            .clipped()

            // Always in reach: the export button, file name and preview stay put while the
            // options above scroll.
            VStack(spacing: 8) {
                if let error {
                    Text(error).font(.osData).foregroundStyle(Sheet.muted)
                }

                // E: the one outlined button.
                Button(busy ? "Preparing…" : format == .photos
                       ? "Save \(shots == 1 ? "1 still" : "\(shots) stills") to Photos"
                       : "\(target == nil ? "Export all scenes" : "Export scene") · \(format == .pdf ? "\(options.tier.label) PDF" : ext.uppercased())") {
                    export(project: project, scene: target)
                }
                .buttonStyle(PillButtonStyle(kind: .outline))

                // Tap the file name to rename the export.
                if format != .photos { HStack(spacing: 0) {
                    EditableName(text: customName ?? defaultName, font: .osData, color: Sheet.muted, title: "File Name") {
                        customName = Exporter.cleanName($0)
                    }
                    Text(".\(ext)").font(.osData).foregroundStyle(Sheet.muted)
                    Image(systemName: "pencil").font(.system(size: 10)).foregroundStyle(Sheet.muted)
                        .padding(.leading, 5).accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity) }

                if format == .pdf {
                    // Look before you send: opens the PDF in Quick Look.
                    Button("Preview the PDF →") { preview(project: project, scene: target) }
                        .buttonStyle(.plain)
                        .font(.osData)
                        .underline()
                        .foregroundStyle(Sheet.text)
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .background(Sheet.bg)
            .overlay(alignment: .top) { Rule() }
        }
        .frame(width: portrait ? nil : 380)
        // E: square edge, a hairline where it meets the screen behind.
        .background(Sheet.bg.ignoresSafeArea())
        .overlay(alignment: .leading) { Sheet.rule.frame(width: 1).ignoresSafeArea() }
        .foregroundStyle(Sheet.text)
        // The Shot List was showing every scene, so start there.
        .onAppear {
            allScenes = scene == nil
            #if DEBUG
            // Screenshot testing: -exportAllScenes YES shows the scene order list.
            if UserDefaults.standard.bool(forKey: "exportAllScenes") { allScenes = true }
            #endif
        }
        .quickLookPreview($previewURL)
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.url])
                .presentationDetents([.large])
                .font(.osRow)
        }
    }

    /// Half of the scope switch: the name big, what's in it small; filled when picked.
    private func scopeHalf(_ title: String, _ sub: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.osTitle)
                Text(sub).font(.osDataSmall).opacity(0.7).lineLimit(1)
            }
            .foregroundStyle(on ? Sheet.bg : Sheet.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(on ? Sheet.text : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// One choice as a small box: the name, its file type, a line on what it's for.
    private func tile(selected: Bool, _ label: String, _ type: String?, _ sub: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(label).font(.osRow)
                    if let type { Text(type).font(.osDataSmall).opacity(0.6) }
                }
                Text(sub).font(.osDataSmall).opacity(0.7).lineLimit(1)
            }
            .foregroundStyle(selected ? Sheet.bg : Sheet.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(selected ? Sheet.text : .clear)
            .overlay(Rectangle().strokeBorder(selected ? Sheet.text : Sheet.rule, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func tierShort(_ t: Exporter.Tier) -> String {
        switch t {
        case .detailed: return "Shot cards, the light"
        case .summary: return "A row per shot"
        case .photos: return "Just the frames"
        }
    }

    /// E include toggle: the word, underlined when it's in the export.
    private func includeChip(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Chip(label: label, selected: on, underline: true, action: action)
    }

    private func preview(project: Project, scene: ScoutScene?) {
        guard !busy else { return }
        busy = true
        var picked = self.options
        picked.kit = store.kit
        let options = picked, name = customName
        // Off the main thread, so the panel stays responsive while the stills are drawn.
        Task {
            await Forecast.prefetch(project: project, scene: scene)
            let url = await Task.detached(priority: .userInitiated) {
                try? Exporter.export(project: project, scene: scene, format: .pdf, options: options, name: name)
            }.value
            busy = false
            previewURL = url
            if url == nil { error = "Couldn't make the preview. Try again." }
        }
    }

    private func export(project: Project, scene: ScoutScene?) {
        if format == .photos {
            let shots = scene?.shots ?? project.scenes.flatMap(\.shots)
            Task {
                do {
                    let n = try await PhotoSaver.save(shots)
                    store.toast = "Saved \(n == 1 ? "1 still" : "\(n) stills") to Photos"
                    error = nil
                } catch PhotoSaver.Failure.nothingToSave {
                    error = "No stills to save yet."
                } catch {
                    self.error = "Couldn't save to Photos. Check access in Settings."
                }
            }
            return
        }
        guard !busy else { return }
        busy = true
        var picked = self.options
        picked.kit = store.kit
        let options = picked, name = customName
        let fileFormat: Exporter.FileFormat = format == .csv ? .csv : .pdf
        Task {
            if fileFormat == .pdf { await Forecast.prefetch(project: project, scene: scene) }
            let url = await Task.detached(priority: .userInitiated) {
                try? Exporter.export(project: project, scene: scene, format: fileFormat, options: options, name: name)
            }.value
            busy = false
            if let url {
                shareItem = ShareItem(url: url)
                error = nil
            } else {
                error = "Couldn't make the file. Try again."
            }
        }
    }
}


/// A drag-to-reorder list: ruled rows 40 high, E style; drag the grip on the right
/// and the row moves as you pass each neighbour, like the v3c board. Tap a name to rename it.
struct OrderList: View {
    struct Row: Identifiable {
        var id: UUID
        var number: String
        var name: String
        var detail: String
    }

    let heading: String
    let renameTitle: String
    let rows: [Row]
    let move: (IndexSet, Int) -> Void
    let rename: (UUID, String) -> Void
    /// Shows a trash icon on each row when set.
    var delete: ((UUID) -> Void)? = nil

    @State private var dragging: UUID?
    private let pitch: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(heading)
                Spacer()
                Text("Drag to reorder")
            }
            .font(.osDataSmall)
            .foregroundStyle(Sheet.muted)

            VStack(spacing: 0) {
                Rule()
                ForEach(rows) { r in row(r) }
            }
            .coordinateSpace(name: "orderList")
            .animation(.snappy(duration: 0.18), value: rows.map(\.id))
        }
    }

    private func row(_ r: Row) -> some View {
        let picked = dragging == r.id
        return HStack(spacing: 10) {
            Text(r.number)
                .font(.osNumSmall).foregroundStyle(Sheet.muted)
                .frame(width: 22, alignment: .leading)
            EditableName(text: r.name, font: .osRow, emptyLabel: "Untitled", title: renameTitle, fillsWidth: true, pencil: true) { rename(r.id, $0) }
            Text(r.detail).font(.osNumSmall).foregroundStyle(Sheet.muted).lineLimit(1)
            if let delete {
                Button { delete(r.id) } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(Sheet.muted)
                        .frame(width: 32, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("delete \(r.name)")
            }
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13))
                .foregroundStyle(Sheet.muted)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named("orderList"))
                        .onChanged { g in
                            if dragging == nil { dragging = r.id }
                            guard let from = rows.firstIndex(where: { $0.id == r.id }) else { return }
                            let to = max(0, min(rows.count - 1, Int(floor(g.location.y / pitch))))
                            if to != from {
                                move(IndexSet(integer: from), to > from ? to + 1 : to)
                            }
                        }
                        .onEnded { _ in dragging = nil }
                )
                .accessibilityLabel("drag to reorder \(r.name)")
        }
        .padding(.trailing, 4)
        .frame(height: 40)
        .background(picked ? Sheet.text.opacity(0.08) : .clear)
        .overlay(alignment: .bottom) { Rule() }
    }
}

/// Scenes in export order, as an OrderList.
struct SceneOrder: View {
    @Environment(ScoutStore.self) private var store
    let scenes: [ScoutScene]
    let move: (IndexSet, Int) -> Void
    var delete: ((UUID) -> Void)? = nil

    var body: some View {
        OrderList(
            heading: "Scene order",
            renameTitle: "Rename Scene",
            rows: scenes.enumerated().map { i, s in
                .init(id: s.id, number: String(format: "%02d", i + 1), name: s.name, detail: ShotListView.shots(s.shots.count))
            },
            move: move,
            rename: { store.renameScene($0, to: $1) },
            delete: delete
        )
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
