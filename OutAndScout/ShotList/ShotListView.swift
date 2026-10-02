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
    @State private var deletingScene: ScoutScene?
    /// The shot shown full screen, for holding the phone up to a director.
    @State private var enlarged: Shot?
    /// Upright: the shot open in the bottom sheet.
    @State private var sheetID: UUID?
    @Environment(\.isPortrait) private var portrait

    var body: some View {
        ZStack {
            Palette.paper.ignoresSafeArea()

            if portrait {
                portraitList
                    .foregroundStyle(Palette.ink)
                portraitSheet
            } else {
                HStack(spacing: 0) {
                    listPane
                        .frame(width: 300)
                    Palette.rule.frame(width: 1).ignoresSafeArea()
                    detailPane
                        .frame(maxWidth: .infinity)
                }
                .foregroundStyle(Palette.ink)
            }

            ZStack {
                if store.showingExport {
                    // v3c: rgba(17,17,17,0.45) behind the panel; tap it to close.
                    Palette.ink.opacity(0.45).ignoresSafeArea()
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
        .animation(.snappy(duration: 0.25), value: sheetID)
        .confirmationDialog(
            "Delete \"\(deletingScene?.name ?? "")\"?",
            isPresented: Binding(get: { deletingScene != nil }, set: { if !$0 { deletingScene = nil } }),
            titleVisibility: .visible,
            presenting: deletingScene
        ) { scene in
            Button("delete \(scene.name)", role: .destructive) {
                if sceneFilter == scene.id { sceneFilter = nil }
                store.deleteScene(scene.id)
                selectedID = nil
                deletingScene = nil
            }
        } message: { scene in
            Text("Its \(Self.shots(scene.shots.count)) go too, stills included. This can't be undone.")
        }
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

            FadingHScroll {
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
                        .contextMenu {
                            // A project always keeps at least one scene.
                            if project.scenes.count > 1 {
                                Button("delete scene", systemImage: "trash", role: .destructive) { deletingScene = s }
                            }
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
                                // Press and hold a shot to delete it; it still asks first.
                                .contextMenu {
                                    Button("delete \(item.shot.number)", systemImage: "trash", role: .destructive) {
                                        selectedID = item.shot.id
                                        confirmDelete = true
                                    }
                                }
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

    // MARK: Portrait (v3c Portrait board)

    /// Header, scene tabs, the shots, and viewfinder / export along the bottom.
    private var portraitList: some View {
        let s = sceneFilter.flatMap(scene(for:)) ?? store.currentScene
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    EditableName(text: project.name, font: .osData, color: Palette.graphite, title: "rename project") {
                        store.renameProject(project.id, to: $0)
                    }
                    Spacer()
                    Text(Format.time(Date())).font(.osData).foregroundStyle(Palette.graphite)
                }
                EditableName(text: s.name, font: Fonts.mono(20), title: "rename scene") { store.renameScene(s.id, to: $0) }
                Text([s.note, Self.shots(s.shots.count)].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.osData).foregroundStyle(Palette.graphite).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.l)
            .padding(.top, 9)
            .padding(.bottom, 12)

            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(project.scenes) { sc in
                        let on = sc.id == s.id
                        Button {
                            sceneFilter = sc.id
                            store.select(project: project.id, scene: sc.id)
                        } label: {
                            HStack(spacing: 4) {
                                Text(sc.name)
                                Text("\(sc.shots.count)").opacity(0.6)
                            }
                            .font(.osData)
                            .foregroundStyle(on ? Palette.paper : Palette.ink)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(on ? Palette.ink : .clear, in: Capsule())
                            .overlay(Capsule().strokeBorder(on ? Palette.ink : Palette.rule, lineWidth: 1))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            // A project always keeps at least one scene.
                            if project.scenes.count > 1 {
                                Button("delete scene", systemImage: "trash", role: .destructive) { deletingScene = sc }
                            }
                        }
                    }
                }
                .padding(.horizontal, Space.l)
            }
            .scrollIndicators(.hidden)
            .padding(.bottom, 12)

            Rule()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(s.shots) { shot in
                        PortraitShotRow(shot: shot)
                            .onTapGesture { sheetID = shot.id }
                            // Press and hold a shot to delete it; it still asks first.
                            .contextMenu {
                                Button("delete \(shot.number)", systemImage: "trash", role: .destructive) {
                                    selectedID = shot.id
                                    confirmDelete = true
                                }
                            }
                    }
                    if s.shots.isEmpty {
                        Text("No shots in this scene yet.")
                            .font(.osRow)
                            .foregroundStyle(Palette.graphite)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 24)
                            .padding(.horizontal, Space.l)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            Rule()
            HStack(spacing: Space.xs) {
                Button { store.showingShotList = false } label: {
                    HStack(spacing: Space.xs) {
                        Image(systemName: "camera.viewfinder").font(.system(size: 14))
                        Text("viewfinder")
                    }
                    .font(.osTitle)
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 1))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                Button { store.showingExport = true } label: {
                    Text("export")
                        .font(.osTitle)
                        .foregroundStyle(Palette.paper)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Palette.ink, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Space.l)
            .padding(.top, 12)
        }
        .confirmationDialog(
            "Delete \(selectedID.flatMap(store.shot)?.number ?? "")?",
            isPresented: Binding(get: { confirmDelete && portrait }, set: { confirmDelete = $0 }),
            titleVisibility: .visible
        ) {
            if let id = selectedID {
                Button("delete \(store.shot(id)?.number ?? "shot")", role: .destructive) {
                    store.deleteShot(id)
                    selectedID = nil
                    sheetID = nil
                }
            }
        }
    }

    /// The shot as a bottom sheet: still, caption, lens / time / light, edit and reframe.
    @ViewBuilder private var portraitSheet: some View {
        if let id = sheetID, let shot = store.shot(id) {
            ZStack(alignment: .bottom) {
                Palette.ink.opacity(0.4).ignoresSafeArea()
                    .onTapGesture { sheetID = nil }
                    .transition(.opacity)

                VStack(alignment: .leading, spacing: 14) {
                    ShotThumb(shot: shot)
                        .frame(maxWidth: .infinity)
                        .frame(height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(alignment: .bottomLeading) {
                            Text("\(shot.number) · \(Format.mm(shot.lensMM))mm · \(Format.time(shot.plannedTime))")
                                .font(.osDataSmall)
                                .foregroundStyle(Palette.paper.opacity(0.8))
                                .padding(.leading, 10)
                                .padding(.bottom, 8)
                        }
                        .onTapGesture { enlarged = shot }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("tap to see it full screen")

                    Text(shot.caption.isEmpty ? "untitled" : shot.caption)
                        .font(Fonts.mono(15))
                        .foregroundStyle(shot.caption.isEmpty ? Palette.graphite : Palette.ink)
                        .lineLimit(3)

                    HStack(alignment: .top, spacing: Space.xs) {
                        sheetCell("lens", "\(Format.mm(shot.lensMM))mm")
                        sheetCell("time", Format.time(shot.plannedTime))
                        sheetCell("light", shot.light.label)
                    }

                    HStack(spacing: Space.xs) {
                        Button {
                            store.rename = RenameRequest(title: "edit caption", text: shot.caption) { [store] in
                                store.setCaption(id, to: $0)
                            }
                        } label: {
                            Text("edit caption")
                                .font(.osRow)
                                .foregroundStyle(Palette.ink)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .overlay(Capsule().strokeBorder(Palette.rule, lineWidth: 1))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        Button {
                            sheetID = nil
                            reframe(shot)
                        } label: {
                            Text("reframe")
                                .font(.osRow)
                                .foregroundStyle(Palette.paper)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Palette.ink, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Space.l)
                .padding(.top, Space.l)
                .padding(.bottom, Space.xs)
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24, style: .continuous)
                        .fill(Palette.paper)
                        .ignoresSafeArea()
                )
                .foregroundStyle(Palette.ink)
                .transition(.move(edge: .bottom))
            }
        }
    }

    private func sheetCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).foregroundStyle(Palette.graphite)
            Text(value).lineLimit(1).minimumScaleFactor(0.8)
        }
        .font(.osData)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                        EditableName(text: shot.caption, font: .osTitle, lineLimit: 3, emptyLabel: "untitled", title: "edit caption") {
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
                FadingHScroll {
                    HStack(spacing: Space.xxs) {
                        Text("frame lines").font(.osDataSmall).foregroundStyle(Palette.graphite)
                            .padding(.trailing, Space.xxs)
                        ForEach([AspectRatio.full(shot.stillAspect ?? AspectRatio.viewfinderValue)] + store.aspectStrip) { a in
                            Chip(label: a.label, selected: a.label == shot.aspect.label, onDark: false) {
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

/// Portrait board row: 72 × 40 still, "1A" in graphite then the caption, lens · time · light.
struct PortraitShotRow: View {
    let shot: Shot

    var body: some View {
        HStack(spacing: 12) {
            ShotThumb(shot: shot)
                .frame(width: 72, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                (Text(shot.number).foregroundStyle(Palette.graphite)
                    + Text(" " + (shot.caption.isEmpty ? "untitled" : shot.caption)))
                    .font(Fonts.mono(13))
                    .lineLimit(1)
                Text("\(Format.mm(shot.lensMM))mm · \(Format.time(shot.plannedTime)) · \(shot.light.label)")
                    .font(.osData)
                    .foregroundStyle(Palette.graphite)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, Space.l)
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
