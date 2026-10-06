import SwiftUI

/// Light panel that slides over the Viewfinder from one edge.
struct SidePanel<Content: View>: View {
    enum Edge { case leading, trailing }
    let edge: Edge
    var width: CGFloat = 380
    @ViewBuilder let content: Content
    @Environment(\.isPortrait) private var portrait

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            content
        }
        .padding(Space.l)
        // Upright the screen is narrower than the panel, so it takes the full width instead.
        .frame(width: portrait ? nil : width)
        .frame(maxHeight: .infinity, alignment: .top)
        .keyboardPadding()
        // E: square edge, a hairline where the panel meets the viewfinder.
        .background(Sheet.bg.ignoresSafeArea())
        .overlay(alignment: edge == .trailing ? .leading : .trailing) {
            Sheet.rule.frame(width: 1).ignoresSafeArea()
        }
        .foregroundStyle(Sheet.text)
    }
}

struct PanelHeader: View {
    let title: String
    let sub: String
    var action: (label: String, run: () -> Void)?

    var body: some View {
        // E: a small caps title, a grey line under it, Done as an underlined word.
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Caps(text: title)
                Text(sub).font(.osData).foregroundStyle(Sheet.muted).lineLimit(1)
            }
            Spacer()
            if let action {
                Button(action.label, action: action.run)
                    .buttonStyle(PillButtonStyle(kind: .text))
            }
        }
    }
}

// MARK: - 06 Projects panel

/// Switch project or scene, add a scene, add a project. One tap from the Viewfinder.
struct ProjectsPanel: View {
    @Environment(ScoutStore.self) private var store
    @State private var expanded: UUID?
    @State private var confirmDeleteAll = false
    /// The project the "delete project" dialog is asking about.
    @State private var deleting: Project?
    /// The scene the "delete scene" dialog is asking about.
    @State private var deletingScene: ScoutScene?

    var body: some View {
        SidePanel(edge: .leading) {
            PanelHeader(
                title: "Projects",
                sub: store.projects.count == 1 ? "1 project" : "\(store.projects.count) projects",
                action: ("Done", { store.panel = nil })
            )
            Rule()

            // E: the open project on top with all its scenes, then the others. Everything,
            // the add and delete buttons too, scrolls together, so a long project never
            // squeezes its scene list into a sliver.
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    let current = store.currentProject
                    VStack(alignment: .leading, spacing: 4) {
                        EditableName(text: current.name, font: Fonts.sans(20, .regular), title: "Rename Project", pencil: true, pencilSize: 13, inPlace: true) {
                            store.renameProject(current.id, to: $0)
                        }
                        summary(current)
                    }
                    .padding(.vertical, Space.xs)
                    .contextMenu {
                        Button("Delete Project", systemImage: "trash", role: .destructive) { deleting = current }
                    }

                    Rule()
                    ForEach(current.scenes) { scene in
                        sceneRow(project: current, scene: scene, indent: false)
                    }
                    Button {
                        store.panel = nil
                        store.requestNewScene()
                    } label: {
                        Text("+ New scene")
                            .font(.osRow)
                            .underline(color: Sheet.muted)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    let others = store.projects.filter { $0.id != current.id }
                    if !others.isEmpty {
                        Caps(text: "Other projects")
                            .foregroundStyle(Sheet.muted)
                            .padding(.top, Space.l)
                            .padding(.bottom, Space.xs)
                        Rule()
                        ForEach(others) { project in
                            projectRow(project)
                            if expanded == project.id {
                                ForEach(project.scenes) { scene in
                                    sceneRow(project: project, scene: scene, indent: true)
                                }
                            }
                        }
                    }

                    // Opens the floating name bar straight away; the project is made when you press Done.
                    Button("+ New project") {
                        store.rename = RenameRequest(title: "New Project", text: "") { [store] in
                            store.addProject(named: $0)
                            store.panel = nil
                        }
                    }
                    .buttonStyle(PillButtonStyle(kind: .text))
                    .padding(.top, Space.xs)

                    // Small and grey on purpose, and it asks first: a clean slate, not a slip.
                    Button("Delete All Projects") { confirmDeleteAll = true }
                        .font(.osSupport)
                        .foregroundStyle(Sheet.muted)
                        .buttonStyle(.plain)
                        .frame(minHeight: 36)
                        .confirmationDialog("Delete every project?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                            Button("Delete All Projects and Shots", role: .destructive) {
                                store.deleteAllProjects()
                                expanded = nil
                            }
                        } message: {
                            Text("All scenes, shots and stills go. You start again with an empty project. This can't be undone.")
                        }
                }
                .padding(.bottom, Space.l)
            }
            .scrollIndicators(.hidden)
            // Always open at the top, with the project name in view.
            .defaultScrollAnchor(.top)
        }
        .confirmationDialog(
            "Delete \"\(deleting?.name ?? "")\"?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { project in
            Button("Delete \(project.name)", role: .destructive) {
                store.deleteProject(project.id)
                expanded = nil
                deleting = nil
            }
        } message: { project in
            let shots = project.scenes.reduce(0) { $0 + $1.shots.count }
            let scenes = project.scenes.count == 1 ? "1 scene" : "\(project.scenes.count) scenes"
            Text("Its \(scenes) and \(ShotListView.shots(shots)) go too, stills included. This can't be undone.")
        }
        .confirmationDialog(
            "Delete \"\(deletingScene?.name ?? "")\"?",
            isPresented: Binding(get: { deletingScene != nil }, set: { if !$0 { deletingScene = nil } }),
            titleVisibility: .visible,
            presenting: deletingScene
        ) { scene in
            Button("Delete \(scene.name)", role: .destructive) {
                store.deleteScene(scene.id)
                deletingScene = nil
            }
        } message: { scene in
            Text("Its \(ShotListView.shots(scene.shots.count)) go too, stills included. This can't be undone.")
        }
    }

    // Tapping a name renames it in place; tapping the rest of the row expands or selects.

    /// "Recce · 11 scenes · 65 shots", numbers in mono.
    private func summary(_ project: Project) -> some View {
        let shots = project.scenes.reduce(0) { $0 + $1.shots.count }
        let kind = project.kind.isEmpty ? Text("") : Text("\(project.kind) · ")
        return (kind
                + Text("\(project.scenes.count)").font(.osNum) + Text(project.scenes.count == 1 ? " scene · " : " scenes · ")
                + Text("\(shots)").font(.osNum) + Text(shots == 1 ? " shot" : " shots"))
            .font(.osData)
            .foregroundStyle(Sheet.muted)
            .lineLimit(1)
    }

    // Another project: tap the name to rename it, the rest of the row to show its scenes.
    private func projectRow(_ project: Project) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
            EditableName(text: project.name, font: .osRow, title: "Rename Project") { store.renameProject(project.id, to: $0) }
            Spacer()
            Text("\(project.scenes.count)").font(.osNum).foregroundStyle(Sheet.muted)
        }
        .frame(minHeight: 40)
        .overlay(alignment: .bottom) { Rule() }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy(duration: 0.2)) { expanded = expanded == project.id ? nil : project.id }
        }
        // Press and hold for delete; it still asks before anything goes.
        .contextMenu {
            Button("Delete Project", systemImage: "trash", role: .destructive) { deleting = project }
        }
    }

    // E: a ruled row; the open scene bright, the rest grey, the shot count in mono.
    private func sceneRow(project: Project, scene: ScoutScene, indent: Bool) -> some View {
        let current = scene.id == store.currentSceneID
        return HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
            EditableName(text: scene.name, font: .osRow, color: current ? Sheet.text : Sheet.muted, title: "Rename Scene") { store.renameScene(scene.id, to: $0) }
            if !scene.note.isEmpty {
                Text(scene.note).font(.osData).foregroundStyle(Sheet.muted).lineLimit(1)
            }
            Spacer()
            Text("\(scene.shots.count)").font(.osNum).foregroundStyle(Sheet.muted)
        }
        .padding(.leading, indent ? Space.m : 0)
        .frame(minHeight: 40)
        .overlay(alignment: .bottom) { Rule() }
        .contentShape(Rectangle())
        .onTapGesture {
            store.select(project: project.id, scene: scene.id)
            store.panel = nil
        }
        .contextMenu {
            // A project always keeps at least one scene.
            if project.scenes.count > 1 {
                Button("Delete Scene", systemImage: "trash", role: .destructive) { deletingScene = scene }
            }
        }
        .accessibilityAddTraits(current ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - 05 Kit panel

/// Cameras, sensor modes and lens sets. Sensor mode changes the crop; anamorphic sets go 2.39.
struct KitPanel: View {
    @Environment(ScoutStore.self) private var store
    @State private var tab = Tab.camera
    @State private var query = ""

    enum Tab { case camera, lenses }

    var body: some View {
        SidePanel(edge: .trailing, width: 440) {
            PanelHeader(
                title: "Your Kit",
                sub: "\(store.kit.camera.name) · \(store.kit.mode.name) · \(store.kit.lenses.name)",
                action: ("Done", { store.panel = nil })
            )

            // Everything under the header scrolls together, so the tabs, sensor modes and
            // search slide away and the list gets the whole panel. The Camera / Lenses tabs
            // stay put under the header, so you can switch without scrolling back up.
            HStack(spacing: Space.l) {
                Chip(label: "Camera", selected: tab == .camera, underline: true) { tab = .camera }
                Chip(label: "Lenses", selected: tab == .lenses, underline: true) { tab = .lenses }
            }
            Rule()
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s) {

                    if tab == .camera, store.kit.camera.modes.count > 1 {
                        Text("Sensor mode").font(.osDataSmall).foregroundStyle(Sheet.muted)
                        FadingHScroll {
                            HStack(spacing: Space.xxs) {
                                ForEach(store.kit.camera.modes) { mode in
                                    Chip(label: mode.name, selected: mode == store.kit.mode, underline: true) {
                                        var kit = store.kit
                                        kit.mode = mode
                                        store.setKit(kit)
                                    }
                                }
                            }
                        }
                    }

                    SheetField(placeholder: "Search kit", text: $query, square: true)

                    LazyVStack(alignment: .leading, spacing: 0) {
                        if tab == .camera {
                            let cams = KitCatalog.cameras.filter(matchesCamera)
                            ForEach(cams) { cam in cameraRow(cam) }
                            if cams.isEmpty { empty }
                        } else {
                            let sets = KitCatalog.lenses.filter(matchesLens)
                            if query.isEmpty { customLensRow }
                            ForEach(sets) { set in lensRow(set) }
                            if sets.isEmpty { empty }
                        }
                    }
                }
                .padding(.bottom, Space.l)
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }

    private var empty: some View {
        Text("Nothing matches. Missing something? It can be requested.")
            .font(.osSupport)
            .foregroundStyle(Sheet.muted)
            .padding(.vertical, Space.m)
    }

    private func matchesCamera(_ c: Camera) -> Bool {
        query.isEmpty || "\(c.brand) \(c.name) \(c.format)".localizedCaseInsensitiveContains(query)
    }

    private func matchesLens(_ l: LensSeries) -> Bool {
        query.isEmpty || "\(l.brand) \(l.name) \(l.type)".localizedCaseInsensitiveContains(query)
    }

    private func cameraRow(_ cam: Camera) -> some View {
        let selected = cam.id == store.kit.camera.id
        return Button {
            var kit = store.kit
            kit.camera = cam
            kit.mode = cam.modes[0]
            store.setKit(kit)
        } label: {
            row(brand: cam.brand, name: cam.name, sub: cam.resolution, tag: cam.format, selected: selected)
        }
        .buttonStyle(.plain)
    }

    /// Your own set: type the focal lengths you carry ("18 25 35 50 85") in the name bar.
    private var customLensRow: some View {
        let current = store.kit.lenses.brand == "Custom" ? store.kit.lenses : nil
        return Button {
            let text = current.map { $0.focals.map(Format.mm).joined(separator: " ") } ?? ""
            store.rename = RenameRequest(title: "Your Lenses, in mm", text: text) { [store] typed in
                let focals = Array(Set(typed
                    .split(whereSeparator: { !"0123456789.".contains($0) })
                    .compactMap { Double($0) }
                    .filter { $0 >= 4 && $0 <= 1200 }))
                    .sorted()
                guard !focals.isEmpty else { return }
                var kit = store.kit
                kit.lenses = LensSeries(brand: "Custom", name: "My Lenses", type: "spherical", focals: focals)
                store.setKit(kit)
            }
        } label: {
            row(brand: "Custom",
                name: current == nil ? "+ Your Own Lenses" : "My Lenses",
                sub: current.map { $0.focals.map(Format.mm).joined(separator: " ") } ?? "Type the focal lengths you carry",
                tag: current == nil ? "" : "Tap to edit",
                selected: current != nil)
        }
        .buttonStyle(.plain)
    }

    private func lensRow(_ set: LensSeries) -> some View {
        let selected = set.id == store.kit.lenses.id
        let focals = set.focals.map(Format.mm).joined(separator: " ")
        return Button {
            var kit = store.kit
            kit.lenses = set
            store.setKit(kit)
        } label: {
            row(brand: set.brand, name: set.name, sub: focals, tag: set.type, selected: selected)
        }
        .buttonStyle(.plain)
    }

    private func row(brand: String, name: String, sub: String, tag: String, selected: Bool) -> some View {
        HStack(alignment: .center, spacing: Space.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(brand).font(.osDataSmall).foregroundStyle(Sheet.muted)
                Text(name).font(.osRow)
                Text(sub).font(.osData).foregroundStyle(Sheet.muted).lineLimit(1)
            }
            Spacer()
            Text(tag).font(.osDataSmall).foregroundStyle(Sheet.muted).lineLimit(1)
            Circle()
                .fill(selected ? Sheet.text : .clear)
                .overlay(Circle().strokeBorder(Sheet.rule, lineWidth: selected ? 0 : 1))
                .frame(width: 10, height: 10)
        }
        .padding(.vertical, 6)
        .frame(minHeight: 48)
        .overlay(alignment: .bottom) { Rule() }
        .contentShape(Rectangle())
    }
}
