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

    enum Choice: String, CaseIterable { case pdf, csv, link }

    var body: some View {
        let project = store.currentProject
        let target = allScenes ? nil : (scene ?? store.currentScene)
        let shots = target.map(\.shots.count) ?? project.scenes.reduce(0) { $0 + $1.shots.count }

        SidePanel(edge: .trailing, width: 440) {
            PanelHeader(
                title: "export shot list",
                sub: "\(project.name) · \(target?.name ?? "all scenes") · \(ShotListView.shots(shots))",
                action: ("done", { store.showingExport = false })
            )

            HStack(spacing: Space.xs) {
                option("this scene", (scene ?? store.currentScene).name, selected: !allScenes) { allScenes = false }
                option("all scenes", project.scenes.count == 1 ? "1 scene" : "\(project.scenes.count) scenes", selected: allScenes) { allScenes = true }
            }

            // All scenes: drag the handles to set the order they go in the PDF and CSV.
            if allScenes && project.scenes.count > 1 {
                List {
                    ForEach(Array(project.scenes.enumerated()), id: \.element.id) { i, s in
                        HStack(spacing: Space.xs) {
                            Text(String(format: "%02d", i + 1)).font(.osData).foregroundStyle(Palette.graphite)
                            Text(s.name).font(.osRow).foregroundStyle(Palette.ink).lineLimit(1)
                            Spacer(minLength: Space.xs)
                            Text(ShotListView.shots(s.shots.count)).font(.osDataSmall).foregroundStyle(Palette.graphite)
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: Space.xs, bottom: 0, trailing: Space.xs))
                    }
                    .onMove { store.moveScenes(from: $0, to: $1) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.editMode, .constant(.active))
                // Takes whatever room is left in the panel, up to three rows; scrolls past that.
                .frame(minHeight: 40, maxHeight: min(CGFloat(project.scenes.count) * 40, 120))
                .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Palette.rule, lineWidth: 1))
            }

            HStack(spacing: Space.xs) {
                option("pdf", nil, selected: format == .pdf) { format = .pdf }
                option("csv", nil, selected: format == .csv) { format = .csv }
                option("link", "soon", selected: format == .link) { format = .link }
                    .opacity(0.5)
                    .disabled(true) // Needs outandscout.com/s/<project> to exist first.
            }

            HStack(spacing: Space.xxs) {
                Chip(label: "frames", selected: options.frames, onDark: false, mono: false) { options.frames.toggle() }
                    .disabled(format == .csv)
                Chip(label: "sun times", selected: options.sunTimes, onDark: false, mono: false) { options.sunTimes.toggle() }
            }

            Spacer(minLength: 0)

            if let error {
                Text(error).font(.osSupport).foregroundStyle(Palette.graphite)
            }

            Button("export \(format.rawValue)") { export(project: project, scene: target) }
                .buttonStyle(PillButtonStyle(kind: .primary))
                .disabled(format == .link)
            // Tap the file name to rename the export.
            let ext = format == .csv ? "csv" : "pdf"
            let defaultName = Exporter.filename(project: project, scene: target, format: format == .csv ? .csv : .pdf)
                .replacingOccurrences(of: ".\(ext)", with: "")
            HStack(spacing: 0) {
                EditableName(text: customName ?? defaultName, font: .osData, color: Palette.graphite, title: "file name") {
                    customName = Exporter.cleanName($0)
                }
                Text(".\(ext)").font(.osData).foregroundStyle(Palette.graphite)
                Image(systemName: "pencil").font(.system(size: 10)).foregroundStyle(Palette.graphite)
                    .padding(.leading, Space.xxs)
            }
            .frame(minHeight: 32)
        }
        // The Shot List was showing every scene, so start there.
        .onAppear { allScenes = scene == nil }
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.url])
                .presentationDetents([.large])
        }
    }

    private func option(_ label: String, _ sub: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.osRow)
                if let sub {
                    Text(sub).font(.osDataSmall).foregroundStyle(Palette.graphite).lineLimit(1)
                }
            }
            .padding(Space.s)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(selected ? Palette.ink : Palette.rule, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
