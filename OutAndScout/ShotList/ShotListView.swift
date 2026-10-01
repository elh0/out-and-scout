import SwiftUI

/// 02 Shot List. The light two-pane screen: scene tabs and shots on the left,
/// the selected shot on the right. Export is one tap away.
struct ShotListView: View {
    @Environment(ScoutStore.self) private var store
    /// nil = all scenes
    @State private var sceneFilter: UUID?
    @State private var selectedID: UUID?
    @State private var confirmDelete = false
    @State private var confirmDeleteAll = false
    /// The shot shown full screen, for holding the phone up to a director.
    @State private var enlarged: Shot?

    var body: some View {
        ZStack {
            Palette.paper.ignoresSafeArea()

            HStack(spacing: 0) {
                listPane
                    .frame(width: 300)
                Palette.rule.frame(width: 1).ignoresSafeArea()
                detailPane
                    .frame(maxWidth: .infinity)
            }
            .foregroundStyle(Palette.ink)

            ZStack {
                if store.showingExport {
                    Color.black.opacity(0.2).ignoresSafeArea()
                        .onTapGesture { store.showingExport = false }
                        .transition(.opacity)
                    ExportPanel(scene: sceneFilter.flatMap(scene(for:)))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .transition(.move(edge: .trailing))
                }
            }
            .animation(.snappy(duration: 0.28), value: store.showingExport)

            if let shot = enlarged {
                ShotViewer(shot: shot) { enlarged = nil }
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .animation(.easeOut(duration: 0.2), value: enlarged?.id)
        .onAppear {
            sceneFilter = store.currentSceneID
            selectedID = store.currentScene.shots.last?.id
        }
    }

    // MARK: Data

    private var project: Project { store.currentProject }

    private func scene(for id: UUID) -> ScoutScene? {
        project.scenes.first { $0.id == id }
    }

    private struct Item: Identifiable {
        var scene: ScoutScene
        var shot: Shot
        var id: UUID { shot.id }
    }

    private var visible: [Item] {
        let scenes = sceneFilter.flatMap(scene(for:)).map { [$0] } ?? project.scenes
        return scenes.flatMap { scene in scene.shots.map { Item(scene: scene, shot: $0) } }
    }

    private var selected: Item? {
        visible.first { $0.shot.id == selectedID } ?? visible.first
    }

    // MARK: List pane

    private var listPane: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Button { store.showingShotList = false } label: {
                    Label("viewfinder", systemImage: "chevron.left")
                        .font(.osSupport)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                if !visible.isEmpty {
                    // Clears every shot in view: this scene, or all scenes. Asks first.
                    Button("delete all") { confirmDeleteAll = true }
                        .font(.osSupport)
                        .foregroundStyle(Palette.graphite)
                        .buttonStyle(.plain)
                        .frame(minHeight: 44)
                        .padding(.trailing, Space.s)
                        .confirmationDialog(
                            "Delete \(visible.count == 1 ? "this shot" : "all \(visible.count) shots") in \(sceneFilter.flatMap(scene(for:))?.name ?? "all scenes")?",
                            isPresented: $confirmDeleteAll,
                            titleVisibility: .visible
                        ) {
                            Button("delete \(Self.shots(visible.count))", role: .destructive) {
                                store.deleteShots(Set(visible.map(\.shot.id)))
                                selectedID = nil
                            }
                        } message: {
                            Text("The stills go too. This can't be undone.")
                        }
                }
                Button("projects") {
                    store.showingShotList = false
                    store.panel = .projects
                }
                .font(.osSupport)
                .buttonStyle(.plain)
                .frame(minHeight: 44)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    Text("shot list · ").font(.osData).foregroundStyle(Palette.graphite)
                    EditableName(text: project.name, font: .osData, color: Palette.graphite, title: "rename project") {
                        store.renameProject(project.id, to: $0)
                    }
                }
                if let s = sceneFilter.flatMap(scene(for:)) {
                    EditableName(text: s.name, font: .osTitle, title: "rename scene") { store.renameScene(s.id, to: $0) }
                } else {
                    Text("all scenes").font(.osTitle).lineLimit(1)
                }
                Text(subtitle).font(.osSupport).foregroundStyle(Palette.graphite)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.xxs) {
                    let total = project.scenes.reduce(0) { $0 + $1.shots.count }
                    Chip(label: "all scenes · \(total)", selected: sceneFilter == nil, onDark: false, mono: false) {
                        sceneFilter = nil
                    }
                    ForEach(project.scenes) { s in
                        Chip(label: "\(s.name) · \(s.shots.count)", selected: sceneFilter == s.id, onDark: false, mono: false) {
                            sceneFilter = s.id
                            store.select(project: project.id, scene: s.id)
                        }
                    }
                    Chip(label: "+ scene", onDark: false, mono: false) {
                        store.showingShotList = false
                        store.requestNewScene()
                    }
                }
            }

            if visible.isEmpty {
                Text("No shots in this scene yet. Pin one from the viewfinder and it lands here.")
                    .font(.osSupport)
                    .foregroundStyle(Palette.graphite)
                    .padding(.top, Space.m)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visible) { item in
                            ShotRow(shot: item.shot, sceneName: sceneFilter == nil ? item.scene.name : nil, selected: item.shot.id == selected?.shot.id)
                                .onTapGesture { selectedID = item.shot.id }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.top, Space.xs)
    }

    private var subtitle: String {
        if let s = sceneFilter.flatMap(scene(for:)) {
            return [s.note, Self.shots(s.shots.count)].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        let scenes = project.scenes.count == 1 ? "1 scene" : "\(project.scenes.count) scenes"
        return "\(scenes) · \(Self.shots(visible.count))"
    }

    // MARK: Detail pane

    @ViewBuilder private var detailPane: some View {
        if let item = selected {
            let shot = item.shot
            VStack(alignment: .leading, spacing: Space.s) {
                HStack(alignment: .top, spacing: Space.l) {
                    ShotThumb(shot: shot)
                        .aspectRatio(shot.aspect.value, contentMode: .fit)
                        .frame(maxWidth: 300, maxHeight: 130)
                        .onTapGesture { enlarged = shot }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("tap to see it full screen")

                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text("\(shot.number) · \(shot.aspect.label) · \(Format.mm(shot.lensMM))mm · \(Format.time(shot.plannedTime))")
                            .font(.osData)
                            .foregroundStyle(Palette.graphite)
                        // Tap the caption to rewrite it; the export uses whatever's here.
                        EditableName(text: shot.caption, font: Fonts.sans(22, .medium), lineLimit: 3, emptyLabel: "untitled", title: "edit caption") {
                            store.setCaption(shot.id, to: $0)
                        }
                        .id(shot.id)
                        HStack(spacing: 0) {
                            EditableName(text: item.scene.name, font: .osSupport, color: Palette.graphite, title: "rename scene") {
                                store.renameScene(item.scene.id, to: $0)
                            }
                            Text(" · \(shot.cameraName)").font(.osSupport).foregroundStyle(Palette.graphite)
                        }
                        if let loc = shot.location {
                            Text(loc.display).font(.osData).foregroundStyle(Palette.graphite).lineLimit(2)
                        }
                    }
                }

                Rule()
                HStack(spacing: 0) {
                    readout("lens", "\(Format.mm(shot.lensMM))mm")
                    readout("time", Format.time(shot.plannedTime))
                    readout("light", shot.light.label, golden: shot.isGolden)
                    readout("sun", "\(Int(shot.sunAzimuth.rounded()))° / \(Int(shot.sunElevation.rounded()))°")
                }
                Rule()

                // Frame lines can be changed after the shot; "full" shows the whole frame.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.xxs) {
                        Text("frame lines").font(.osDataSmall).foregroundStyle(Palette.graphite)
                            .padding(.trailing, Space.xxs)
                        ForEach([AspectRatio.full] + store.aspectStrip) { a in
                            Chip(label: a.label, selected: a == shot.aspect, onDark: false) {
                                store.setShotAspect(shot.id, to: a)
                            }
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Space.xs) {
                    Button("delete") { confirmDelete = true }
                        .buttonStyle(PillButtonStyle(kind: .secondary))
                    Button("reframe") { reframe(shot) }
                        .buttonStyle(PillButtonStyle(kind: .secondary))
                    Spacer()
                    Button("export list") { store.showingExport = true }
                        .buttonStyle(PillButtonStyle(kind: .primary))
                        .frame(maxWidth: 200)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.l)
            .confirmationDialog("Delete \(shot.number)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("delete \(shot.number)", role: .destructive) {
                    store.deleteShot(shot.id)
                    selectedID = nil
                }
            }
        } else {
            VStack(spacing: Space.m) {
                Spacer()
                Text("Pin a shot from the viewfinder to see it here.")
                    .font(.osSupport)
                    .foregroundStyle(Palette.graphite)
                Spacer()
            }
        }
    }

    static func shots(_ n: Int) -> String { n == 1 ? "1 shot" : "\(n) shots" }

    private func readout(_ label: String, _ value: String, golden: Bool? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.osDataSmall).foregroundStyle(Palette.graphite)
            HStack(spacing: Space.xxs) {
                if let golden { LightDot(golden: golden) }
                Text(value).font(.osData).lineLimit(1).minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Back to the viewfinder with this shot's lens, aspect and time.
    private func reframe(_ shot: Shot) {
        // Snap to the nearest focal in the current kit, as switching kits does.
        store.lensMM = store.focalLengths.min { abs($0 - shot.lensMM) < abs($1 - shot.lensMM) } ?? shot.lensMM
        store.setAspect(shot.aspect)
        let c = Calendar.current.dateComponents([.hour, .minute], from: shot.plannedTime)
        store.plannedMinutes = Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
        store.showingShotList = false
    }
}

/// Thumb, number, title, mono meta, light dot.
struct ShotRow: View {
    let shot: Shot
    var sceneName: String?
    let selected: Bool

    var body: some View {
        HStack(spacing: Space.s) {
            ShotThumb(shot: shot)
                .frame(width: 64, height: 64 / max(shot.aspect.value, 1))
            Text(shot.number)
                .font(.osData)
                .foregroundStyle(Palette.graphite)
                .frame(width: 28, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(shot.caption.isEmpty ? "untitled" : shot.caption).font(.osRow).lineLimit(1)
                Text(sceneName.map { "\($0) · \(shot.meta)" } ?? shot.meta)
                    .font(.osData)
                    .foregroundStyle(Palette.graphite)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            LightDot(golden: shot.isGolden)
        }
        .padding(.vertical, Space.xs)
        .padding(.horizontal, Space.xs)
        .frame(minHeight: 56)
        .background(selected ? Palette.ink.opacity(0.05) : .clear, in: RoundedRectangle(cornerRadius: Radius.readout))
        .overlay(alignment: .bottom) { Rule() }
        .contentShape(Rectangle())
    }
}

/// One still, as big as the screen allows, cropped to its frame lines. Tap to close.
struct ShotViewer: View {
    let shot: Shot
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Color(hex: 0x2B2B28)
                .overlay {
                    if let image = ThumbCache.full(for: shot) {
                        Image(uiImage: image).resizable().scaledToFill()
                    }
                }
                .aspectRatio(shot.aspect.value, contentMode: .fit)
                .clipped()
                .padding(.vertical, Space.xs)

            VStack {
                Spacer()
                Text("\(shot.number) · \(shot.caption.isEmpty ? "untitled" : shot.caption) · \(Format.mm(shot.lensMM))mm · \(shot.aspect.label)")
                    .font(.osData)
                    .foregroundStyle(Palette.paper)
                    .padding(.horizontal, Space.xs)
                    .padding(.vertical, Space.xxs + 1)
                    .background(Palette.hud, in: RoundedRectangle(cornerRadius: Radius.readout))
                    .padding(.bottom, Space.s)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onClose)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("close full screen")
    }
}
