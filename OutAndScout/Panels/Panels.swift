import SwiftUI

/// Light panel that slides over the Viewfinder from one edge.
struct SidePanel<Content: View>: View {
    enum Edge { case leading, trailing }
    let edge: Edge
    var width: CGFloat = 380
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            content
        }
        .padding(Space.l)
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .keyboardPadding()
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: edge == .trailing ? Radius.sheet : 0,
                bottomLeadingRadius: edge == .trailing ? Radius.sheet : 0,
                bottomTrailingRadius: edge == .leading ? Radius.sheet : 0,
                topTrailingRadius: edge == .leading ? Radius.sheet : 0,
                style: .continuous
            )
            .fill(Palette.paper)
            .ignoresSafeArea()
        )
        .foregroundStyle(Palette.ink)
    }
}

struct PanelHeader: View {
    let title: String
    let sub: String
    var action: (label: String, run: () -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Font.osTitle)
                Text(sub).font(.osData).foregroundStyle(Palette.graphite).lineLimit(1)
            }
            Spacer()
            if let action {
                Button(action.label, action: action.run)
                    .buttonStyle(PillButtonStyle(kind: .secondary))
            }
        }
    }
}

// MARK: - 06 Projects panel

/// Switch project or scene, add a scene, add a project. One tap from the Viewfinder.
struct ProjectsPanel: View {
    @Environment(ScoutStore.self) private var store
    @State private var expanded: UUID?
    @State private var newName = ""
    @State private var confirmDeleteAll = false
    /// The project the "delete project" dialog is asking about.
    @State private var deleting: Project?
    /// The scene the "delete scene" dialog is asking about.
    @State private var deletingScene: ScoutScene?

    var body: some View {
        SidePanel(edge: .leading) {
            PanelHeader(
                title: "projects",
                sub: store.projects.count == 1 ? "1 project" : "\(store.projects.count) projects",
                action: ("done", { store.panel = nil })
            )
            Rule()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(store.projects) { project in
                        projectRow(project)
                        if expanded == project.id {
                            ForEach(project.scenes) { scene in
                                sceneRow(project: project, scene: scene)
                            }
                            Button {
                                store.select(project: project.id)
                                store.panel = nil
                                store.requestNewScene()
                            } label: {
                                Text("+ scene")
                                    .font(.osSupport)
                                    .padding(.leading, Space.m)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        Rule()
                    }
                }
            }

            HStack(spacing: Space.xs) {
                SheetField(placeholder: "new project name", text: $newName, onSubmit: addProject)
                Button("+ new project", action: addProject)
                    .buttonStyle(PillButtonStyle(kind: .secondary))
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            // Small and grey on purpose, and it asks first: a clean slate, not a slip.
            Button("delete all projects") { confirmDeleteAll = true }
                .font(.osSupport)
                .foregroundStyle(Palette.graphite)
                .buttonStyle(.plain)
                .frame(minHeight: 36)
                .confirmationDialog("Delete every project?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                    Button("delete all projects and shots", role: .destructive) {
                        store.deleteAllProjects()
                        expanded = store.currentProjectID
                    }
                } message: {
                    Text("All scenes, shots and stills go. You start again with an empty project. This can't be undone.")
                }
        }
        .confirmationDialog(
            "Delete \"\(deleting?.name ?? "")\"?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { project in
            Button("delete \(project.name)", role: .destructive) {
                store.deleteProject(project.id)
                expanded = store.currentProjectID
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
            Button("delete \(scene.name)", role: .destructive) {
                store.deleteScene(scene.id)
                deletingScene = nil
            }
        } message: { scene in
            Text("Its \(ShotListView.shots(scene.shots.count)) go too, stills included. This can't be undone.")
        }
        .onAppear { expanded = store.currentProjectID }
    }

    // Tapping a name renames it in place; tapping the rest of the row expands or selects.

    private func projectRow(_ project: Project) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
            EditableName(text: project.name, font: .osRow, title: "rename project") { store.renameProject(project.id, to: $0) }
            if !project.kind.isEmpty {
                Text(project.kind).font(.osSupport).foregroundStyle(Palette.graphite)
            }
            Spacer()
            Text(project.scenes.count == 1 ? "1 scene" : "\(project.scenes.count) scenes")
                .font(.osData).foregroundStyle(Palette.graphite)
        }
        .frame(minHeight: 48)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy(duration: 0.2)) { expanded = expanded == project.id ? nil : project.id }
        }
        // Press and hold for delete; it still asks before anything goes.
        .contextMenu {
            Button("delete project", systemImage: "trash", role: .destructive) { deleting = project }
        }
    }

    private func sceneRow(project: Project, scene: ScoutScene) -> some View {
        let current = scene.id == store.currentSceneID
        return HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
            EditableName(text: scene.name, font: current ? .osRow : .osSupport, title: "rename scene") { store.renameScene(scene.id, to: $0) }
            Text(scene.note).font(.osData).foregroundStyle(Palette.graphite)
            Spacer()
            Text("\(scene.shots.count)").font(.osData).foregroundStyle(Palette.graphite)
        }
        .padding(.leading, Space.m)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture {
            store.select(project: project.id, scene: scene.id)
            store.panel = nil
        }
        .contextMenu {
            // A project always keeps at least one scene.
            if project.scenes.count > 1 {
                Button("delete scene", systemImage: "trash", role: .destructive) { deletingScene = scene }
            }
        }
        .accessibilityAddTraits(current ? [.isButton, .isSelected] : .isButton)
    }

    private func addProject() {
        store.addProject(named: newName)
        newName = ""
        store.panel = nil
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
                title: "your kit",
                sub: "\(store.kit.camera.name.lowercased()) · \(store.kit.mode.name) · \(store.kit.lenses.name.lowercased())",
                action: ("done", { store.panel = nil })
            )

            HStack(spacing: Space.xxs) {
                Chip(label: "camera", selected: tab == .camera, onDark: false, mono: false) { tab = .camera }
                Chip(label: "lenses", selected: tab == .lenses, onDark: false, mono: false) { tab = .lenses }
            }

            if tab == .camera, store.kit.camera.modes.count > 1 {
                Text("sensor mode").font(.osDataSmall).foregroundStyle(Palette.graphite)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.xxs) {
                        ForEach(store.kit.camera.modes) { mode in
                            Chip(label: mode.name, selected: mode == store.kit.mode, onDark: false) {
                                var kit = store.kit
                                kit.mode = mode
                                store.setKit(kit)
                            }
                        }
                    }
                }
            }

            SheetField(placeholder: "search kit", text: $query)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if tab == .camera {
                        let cams = KitCatalog.cameras.filter(matchesCamera)
                        ForEach(cams) { cam in cameraRow(cam) }
                        if cams.isEmpty { empty }
                    } else {
                        let sets = KitCatalog.lenses.filter(matchesLens)
                        ForEach(sets) { set in lensRow(set) }
                        if sets.isEmpty { empty }
                    }
                }
            }
        }
    }

    private var empty: some View {
        Text("Nothing matches. Missing something? It can be requested.")
            .font(.osSupport)
            .foregroundStyle(Palette.graphite)
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
                Text(brand.lowercased()).font(.osDataSmall).foregroundStyle(Palette.graphite)
                Text(name).font(.osRow)
                Text(sub).font(.osData).foregroundStyle(Palette.graphite).lineLimit(1)
            }
            Spacer()
            Text(tag).font(.osDataSmall).foregroundStyle(Palette.graphite).lineLimit(1)
            Circle()
                .fill(selected ? Palette.ink : .clear)
                .overlay(Circle().strokeBorder(Palette.rule, lineWidth: selected ? 0 : 1))
                .frame(width: 10, height: 10)
        }
        .padding(.vertical, Space.xs)
        .frame(minHeight: 56)
        .overlay(alignment: .bottom) { Rule() }
        .contentShape(Rectangle())
    }
}
