import PDFKit
import SwiftUI
import UIKit

/// The export sheet, outline look round 4 (locked 8 Oct 2026). A card over the Shot List:
/// on the left, this scene or all scenes, the three PDFs as cards with a round tick, and
/// Frames / Sun / Notes; on the right, the real A4 pages as they'll be sent (Fit, 50%, 75%),
/// the file name, Cancel and Export PDF. Once made, a done view with the share sheet.
/// Upright, the same pieces stack in one scrolling column.
struct ExportPanel: View {
    @Environment(ScoutStore.self) private var store
    @Environment(\.isPortrait) private var portrait
    /// The scene the Shot List is showing, or nil for all scenes.
    let scene: ScoutScene?

    @State private var allScenes = false
    @State private var options = Exporter.Options()
    /// A name typed over the default file name, without the extension.
    @State private var customName: String?
    /// The PDF for the current choices, rebuilt a moment after each change.
    @State private var pdf: Data?
    @State private var building = false
    @State private var zoom = Zoom.fit
    /// The file made by Export PDF; shows the done view.
    @State private var made: URL?
    @State private var shareItem: ShareItem?
    @State private var busy = false
    @State private var error: String?
    @State private var forecastReady = false

    enum Zoom: String, CaseIterable {
        case fit = "Fit", half = "50%", threeQuarter = "75%"
        /// Points on screen per PDF point; nil fits the page width.
        var scale: CGFloat? {
            switch self {
            case .fit: return nil
            case .half: return 0.5
            case .threeQuarter: return 0.75
            }
        }
    }

    private var project: Project { store.currentProject }
    private var thisScene: ScoutScene { scene ?? store.currentScene }
    private var target: ScoutScene? { allScenes ? nil : thisScene }
    private var shotCount: Int {
        target?.shots.count ?? project.scenes.reduce(0) { $0 + $1.shots.count }
    }
    private var defaultName: String {
        Exporter.filename(project: project, scene: target, format: .pdf).replacingOccurrences(of: ".pdf", with: "")
    }
    /// Everything the pages depend on; a change rebuilds the preview.
    private var previewKey: String {
        let shots = (target.map { [$0] } ?? project.scenes).flatMap(\.shots)
        let names = shots.map { "\($0.id)\($0.caption)\($0.notes ?? "")" }.joined()
        return "\(allScenes)\(options.tier)\(options.frames)\(options.sunTimes)\(options.notes)\(project.name)\(names.hashValue)\(forecastReady)"
    }

    var body: some View {
        Group {
            if portrait { uprightSheet } else { wideSheet }
        }
        .background(RoundedRectangle(cornerRadius: 18).fill(Outline.card))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Outline.line, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .foregroundStyle(Sheet.text)
        .onAppear {
            allScenes = scene == nil
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "exportAllScenes") { allScenes = true }
            #endif
        }
        .task {
            // The Detailed pages carry the week's weather; fetch it once, then rebuild.
            await Forecast.prefetch(project: project, scene: nil)
            forecastReady = true
        }
        .task(id: previewKey) { await rebuild() }
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.url])
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: Layouts

    /// Landscape: options on the left, the pages and buttons on the right.
    private var wideSheet: some View {
        HStack(alignment: .top, spacing: 18) {
            ScrollView {
                optionsColumn(width: 200)
                    .padding(.vertical, 16)
            }
            .scrollIndicators(.hidden)
            .frame(width: 200)

            Rectangle().fill(Outline.line).frame(width: 1)

            if let made {
                doneView(made)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("TAP EXPORT TO SEND THESE PAGES")
                            .font(Fonts.mono(8)).tracking(0.6).foregroundStyle(Sheet.muted)
                        preview
                    }
                    .padding(.vertical, 16)
                    sideColumn
                        .frame(width: 132)
                        .padding(.vertical, 16)
                }
            }
        }
        .padding(.horizontal, 18)
    }

    /// Upright: one column, the pages in the middle, the buttons always at the bottom.
    private var uprightSheet: some View {
        VStack(spacing: 0) {
            if let made {
                doneView(made).padding(18)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        optionsColumn(width: nil)
                        preview.frame(height: 380)
                        fileRow
                        zoomRow
                    }
                    .padding(18)
                }
                .scrollIndicators(.hidden)
                Rectangle().fill(Outline.line).frame(height: 1)
                HStack(spacing: 8) {
                    OPill(label: "Cancel", size: .big, caps: true) { close() }
                    Spacer(minLength: 0)
                    OPill(label: busy ? "Making…" : "Export PDF", on: true, size: .big, caps: true) { exportPDF() }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
            }
        }
    }

    // MARK: Pieces

    /// Title, scope, the three tiers, what's included, and the other ways out.
    private func optionsColumn(width: CGFloat?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Export").font(.osSans(18))
            HStack(spacing: 6) {
                OPill(label: "This scene", on: !allScenes, size: .small) { allScenes = false }
                OPill(label: "All scenes", on: allScenes, size: .small) { allScenes = true }
            }
            .padding(.top, 12)
            .padding(.bottom, 14)

            VStack(spacing: 6) {
                ForEach(Exporter.Tier.allCases, id: \.self) { t in tierCard(t) }
            }

            HStack(spacing: 12) {
                include("Frames", on: options.frames) { options.frames.toggle() }
                include("Sun", on: options.sunTimes) { options.sunTimes.toggle() }
                include("Notes", on: options.notes) { options.notes.toggle() }
            }
            .padding(.top, 6)

            HStack(spacing: 4) {
                Text("ALSO:").foregroundStyle(Sheet.muted)
                Button("SPREADSHEET") { exportCSV() }
                    .buttonStyle(.plain).underline()
                Text("·").foregroundStyle(Sheet.muted)
                Button("PHOTOS APP") { saveToPhotos() }
                    .buttonStyle(.plain).underline()
            }
            .font(Fonts.mono(8))
            .tracking(0.6)
            .frame(minHeight: 32)

            if let error {
                Text(error).font(Fonts.mono(9)).foregroundStyle(Sheet.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: width, alignment: .leading)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }

    private func tierCard(_ t: Exporter.Tier) -> some View {
        let on = options.tier == t
        return Button { options.tier = t } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(t.label).font(.osSans(13))
                    Text(tierLine(t)).font(Fonts.mono(9)).foregroundStyle(Sheet.muted)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                TickBox(on: on, round: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(on ? Sheet.text : Outline.line, lineWidth: 1.5))
            .background(RoundedRectangle(cornerRadius: 14).stroke(on ? Outline.ring : .clear, lineWidth: 3).padding(-1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(OPressRing())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func tierLine(_ t: Exporter.Tier) -> String {
        switch t {
        case .detailed: return "Shot cards: light, sun, best time"
        case .summary: return "One line per shot"
        case .photos: return "Just the frames"
        }
    }

    private func include(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                TickBox(on: on)
                Text(label.uppercased()).font(Fonts.mono(9)).tracking(0.6)
                    .foregroundStyle(on ? Sheet.text : Sheet.muted)
            }
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// The real pages, on a dark well.
    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x0C0C0B))
            if let pdf {
                PDFPages(data: pdf, scale: zoom.scale)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            if building || pdf == nil {
                Text(pdf == nil ? "MAKING THE PAGES…" : "UPDATING…")
                    .font(Fonts.mono(8)).tracking(0.6).foregroundStyle(Sheet.muted)
                    .padding(6)
                    .background(Capsule().fill(Outline.card.opacity(0.9)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: pdf == nil ? .center : .top)
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// File name, pages and zoom, then Cancel and Export PDF.
    private var sideColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            fileRow
            zoomRow.padding(.top, 10)
            Spacer(minLength: 12)
            OPill(label: "Cancel", size: .big, caps: true) { close() }
            OPill(label: busy ? "Making…" : "Export PDF", on: true, size: .big, caps: true) { exportPDF() }
        }
    }

    private var fileRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("FILE").font(Fonts.mono(8)).tracking(0.6).foregroundStyle(Sheet.muted)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                EditableName(text: customName ?? defaultName, font: Fonts.mono(10), lineLimit: 3, title: "File Name", inPlace: true) {
                    customName = Exporter.cleanName($0)
                }
                Text(".pdf").font(Fonts.mono(10)).foregroundStyle(Sheet.muted)
            }
        }
    }

    private var zoomRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(pageCount) PAGE\(pageCount == 1 ? "" : "S") · ZOOM")
                .font(Fonts.mono(8)).tracking(0.6).foregroundStyle(Sheet.muted)
            HStack(spacing: 6) {
                ForEach(Zoom.allCases, id: \.self) { z in
                    OPill(label: z.rawValue, on: zoom == z, size: .small) { zoom = z }
                }
            }
        }
    }

    private var pageCount: Int {
        guard let pdf, let doc = PDFDocument(data: pdf) else { return 0 }
        return doc.pageCount
    }

    /// The file is ready: its name, what's in it, the share sheet, and a way back.
    private func doneView(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("READY").font(Fonts.mono(9)).tracking(0.6).foregroundStyle(Sheet.muted)
            Text(url.lastPathComponent).font(.osSans(20)).lineLimit(3)
            Text("\(pageCount) PAGE\(pageCount == 1 ? "" : "S") · \(ShotListView.shots(shotCount).uppercased()) · \(options.tier.label.uppercased())")
                .font(Fonts.mono(9)).tracking(0.6).foregroundStyle(Sheet.muted)
            OPill(label: "Send · AirDrop, Mail, Files", on: true, size: .big) { shareItem = ShareItem(url: url) }
                .padding(.top, 10)
            Spacer(minLength: 20)
            HStack(spacing: 8) {
                OPill(label: "Edit again", caps: true) { made = nil }
                OPill(label: "Done", on: true, caps: true) { close() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.vertical, portrait ? 0 : 24)
    }

    // MARK: Actions

    private func close() { store.showingExport = false }

    /// Builds the pages off the main thread, a beat after the last change.
    private func rebuild() async {
        try? await Task.sleep(for: .milliseconds(pdf == nil ? 0 : 250))
        guard !Task.isCancelled else { return }
        building = true
        var picked = options
        picked.kit = store.kit
        let opts = picked, proj = project
        let scenes = target.map { [$0] } ?? proj.scenes
        let data = await Task.detached(priority: .userInitiated) {
            Exporter.pdf(project: proj, scenes: scenes, options: opts)
        }.value
        guard !Task.isCancelled else { return }
        pdf = data
        building = false
    }

    private func exportPDF() {
        guard !busy else { return }
        busy = true
        error = nil
        var picked = options
        picked.kit = store.kit
        let opts = picked, proj = project, scene = target, name = customName, ready = building ? nil : pdf
        Task {
            let url = await Task.detached(priority: .userInitiated) { () -> URL? in
                if let ready {
                    let url = Exporter.fileURL(project: proj, scene: scene, format: .pdf, name: name)
                    do { try ready.write(to: url, options: .atomic); return url } catch { return nil }
                }
                return try? Exporter.export(project: proj, scene: scene, format: .pdf, options: opts, name: name)
            }.value
            busy = false
            if let url { made = url } else { error = "Couldn't make the PDF. Try again." }
        }
    }

    private func exportCSV() {
        var picked = options
        picked.kit = store.kit
        let opts = picked, proj = project, scene = target
        Task {
            let url = await Task.detached(priority: .userInitiated) {
                try? Exporter.export(project: proj, scene: scene, format: .csv, options: opts)
            }.value
            if let url { shareItem = ShareItem(url: url); error = nil } else { error = "Couldn't make the spreadsheet." }
        }
    }

    private func saveToPhotos() {
        let shots = target?.shots ?? project.scenes.flatMap(\.shots)
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
    }
}

/// The PDF's pages, scrolling down, at a set scale or fitted to the width.
struct PDFPages: UIViewRepresentable {
    let data: Data
    /// Points on screen per PDF point; nil fits the width.
    let scale: CGFloat?

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.displaysPageBreaks = true
        v.pageBreakMargins = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        v.backgroundColor = .clear
        v.pageShadowsEnabled = false
        return v
    }

    func updateUIView(_ v: PDFView, context: Context) {
        if context.coordinator.data != data {
            context.coordinator.data = data
            // Keep the reader on the same page when the options change.
            let index = v.currentPage.flatMap { v.document?.index(for: $0) } ?? 0
            v.document = PDFDocument(data: data)
            if let doc = v.document, doc.pageCount > 0, let page = doc.page(at: min(index, doc.pageCount - 1)) {
                v.go(to: page)
            }
        }
        if let scale {
            v.autoScales = false
            v.minScaleFactor = 0.1
            v.maxScaleFactor = 4
            v.scaleFactor = scale
        } else {
            v.autoScales = true
            // Re-fit once laid out, so the whole page width shows.
            DispatchQueue.main.async {
                v.minScaleFactor = 0.1
                v.scaleFactor = v.scaleFactorForSizeToFit
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var data: Data? }
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
