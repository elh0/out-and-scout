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

/// As in the prototype (flow.html): the wordmark, PROJECTS with Edit and Done, then one ruled
/// list of projects. The open project carries a dot and its scenes underneath; a tap opens a
/// project or a scene and closes the panel. Rename and Delete only show after Edit.
struct ProjectsPanel: View {
    @Environment(ScoutStore.self) private var store
    @Environment(\.isPortrait) private var portrait
    @State private var editing = false
    @State private var confirmDeleteAll = false
    /// The project the "delete project" dialog is asking about.
    @State private var deleting: Project?
    /// The scene the "delete scene" dialog is asking about.
    @State private var deletingScene: ScoutScene?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Wordmark(size: 15)
                .padding(.top, 2)
                .padding(.bottom, Space.m)

            HStack(alignment: .firstTextBaseline) {
                Caps(text: "Projects")
                Spacer()
                HStack(spacing: Space.m) {
                    Button(editing ? "Stop editing" : "Edit") {
                        withAnimation(.snappy(duration: 0.2)) { editing.toggle() }
                    }
                    .buttonStyle(UnderlinedWord())
                    Button("Done") { store.panel = nil }
                        .buttonStyle(UnderlinedWord())
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Rule()
                    ForEach(store.projects) { project in
                        projectRow(project)
                        if project.id == store.currentProjectID, !editing {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(project.scenes) { scene in
                                    sceneRow(project: project, scene: scene)
                                }
                            }
                            .padding(.leading, 14)
                            .padding(.top, 2)
                            .padding(.bottom, Space.xs)
                            .overlay(alignment: .bottom) { Rule() }
                        }
                    }

                    if editing {
                        // Small and grey on purpose, and it asks first: a clean slate, not a slip.
                        Button("Delete all projects") { confirmDeleteAll = true }
                            .font(.osSupport)
                            .foregroundStyle(Sheet.muted)
                            .buttonStyle(.plain)
                            .frame(minHeight: 40)
                            .padding(.top, Space.xs)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(.top)
            .padding(.top, 14)

            // Pinned under the list: made at once as "Untitled N", straight to the camera.
            Button {
                let n = store.projects.filter { $0.name.hasPrefix("Untitled") }.count + 1
                store.addProject(named: "Untitled \(n)")
                store.panel = nil
                store.toast = "New project. Rename it under Edit."
            } label: {
                Text("+ New project")
                    .font(.osRow)
                    .foregroundStyle(Sheet.text.opacity(0.62))
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        // Prototype: 380 from the screen edge (336 plus the ~47 safe area), clear of the notch on the left, ink to every edge.
        .padding(.top, 18)
        .padding(.bottom, Space.xs)
        .padding(.leading, portrait ? Space.l : Space.xs)
        .padding(.trailing, portrait ? Space.l : 28)
        .frame(width: portrait ? nil : 336)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Sheet.bg.ignoresSafeArea())
        .overlay(alignment: .trailing) {
            Sheet.rule.frame(width: 1).ignoresSafeArea()
        }
        .foregroundStyle(Sheet.text)
        .confirmationDialog("Delete every project?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Delete All Projects and Shots", role: .destructive) {
                store.deleteAllProjects()
                editing = false
            }
        } message: {
            Text("All scenes, shots and stills go. You start again with an empty project. This can't be undone.")
        }
        .confirmationDialog(
            "Delete \"\(deleting?.name ?? "")\"?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { project in
            Button("Delete \(project.name)", role: .destructive) {
                store.deleteProject(project.id)
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

    /// Name 14, a dot after the open one, "3 sc · 7" in grey; Rename / Delete after Edit.
    private func projectRow(_ project: Project) -> some View {
        let isCurrent = project.id == store.currentProjectID
        let shots = project.scenes.reduce(0) { $0 + $1.shots.count }
        return HStack(alignment: .center, spacing: Space.s) {
            HStack(spacing: Space.xs) {
                Text(project.name).font(Fonts.mono(14)).foregroundStyle(Sheet.text).lineLimit(1)
                if isCurrent {
                    Circle().fill(Sheet.text).frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
            }
            Spacer(minLength: Space.xs)
            if editing {
                editButtons(
                    rename: {
                        store.rename = RenameRequest(title: "Rename Project", text: project.name) { [store] in
                            store.renameProject(project.id, to: $0)
                        }
                    },
                    delete: { deleting = project }
                )
            } else {
                Text("\(project.scenes.count) sc · \(shots)")
                    .font(.osNum).foregroundStyle(Sheet.muted)
            }
        }
        .padding(.vertical, 11)
        .frame(minHeight: 44)
        .overlay(alignment: .bottom) { Rule() }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !editing else { return }
            store.select(project: project.id)
            store.panel = nil
        }
        .swipeToDelete(enabled: !editing) { deleting = project }
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("opens this project")
    }

    /// Edit mode's two words on a row: Rename, and Delete in the sun's orange.
    private func editButtons(rename: @escaping () -> Void, delete: (() -> Void)?) -> some View {
        HStack(spacing: 14) {
            Button("Rename", action: rename)
                .font(.osRow).foregroundStyle(Sheet.text).buttonStyle(.plain)
                .frame(minHeight: 40)
            if let delete {
                Button("Delete", action: delete)
                    .font(.osRow).foregroundStyle(Palette.sun).buttonStyle(.plain)
                    .frame(minHeight: 40)
            }
        }
    }

    /// Indented under the open project: grey, the open scene bright, shot count on the right.
    private func sceneRow(project: Project, scene: ScoutScene) -> some View {
        let current = scene.id == store.currentSceneID
        return HStack(alignment: .firstTextBaseline) {
            Text(scene.name).font(.osRow).lineLimit(1)
            Spacer()
            Text("\(scene.shots.count)").font(.osNum)
        }
        .foregroundStyle(current ? Sheet.text : Sheet.text.opacity(0.62))
        .padding(.vertical, 6)
        .frame(minHeight: 30)
        .contentShape(Rectangle())
        .onTapGesture {
            store.select(project: project.id, scene: scene.id)
            store.panel = nil
        }
        // A project always keeps at least one scene.
        .swipeToDelete(enabled: project.scenes.count > 1) { deletingScene = scene }
        .contextMenu {
            Button("Rename Scene", systemImage: "pencil") {
                store.rename = RenameRequest(title: "Rename Scene", text: scene.name) { [store] in
                    store.renameScene(scene.id, to: $0)
                }
            }
            // A project always keeps at least one scene.
            if project.scenes.count > 1 {
                Button("Delete Scene", systemImage: "trash", role: .destructive) { deletingScene = scene }
            }
        }
        .accessibilityAddTraits(current ? [.isButton, .isSelected] : .isButton)
    }
}

/// A word with a grey underline, as the prototype's Edit and Done.
struct UnderlinedWord: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.osRow)
            .foregroundStyle(Sheet.text)
            .padding(.bottom, 1)
            .overlay(alignment: .bottom) { Sheet.muted.frame(height: 1) }
            .frame(minHeight: 36)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.5 : 1)
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
