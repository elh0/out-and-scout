import SwiftUI

/// 02 Shot List. The light two-pane screen: scene tabs and shots on the left,
/// the selected shot on the right. Export is one tap away.
struct ShotListView: View {
    @Environment(ScoutStore.self) private var store
    /// nil = all scenes
    @State private var sceneFilter: UUID?
    /// The drag-to-reorder scenes sheet, opened by holding a scene.
    @State private var reordering = false
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
            Sheet.bg.ignoresSafeArea()

            if portrait {
                portraitList
                    .foregroundStyle(Sheet.text)
                portraitSheet
            } else {
                HStack(spacing: 0) {
                    listPane
                        .frame(width: 300)
                    Sheet.rule.frame(width: 1).ignoresSafeArea()
                    detailPane
                        .frame(maxWidth: .infinity)
                }
                .foregroundStyle(Sheet.text)
            }

            ZStack {
                if store.showingExport {
                    // v3c: rgba(17,17,17,0.45) behind the panel; tap it to close.
                    Color.black.opacity(0.55).ignoresSafeArea()
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
        .sheet(isPresented: $reordering) {
            let project = store.currentProject
            VStack(alignment: .leading, spacing: 16) {
                PanelHeader(title: "Order and Names", sub: "Tap a name to rename, drag to reorder. Exports follow this.", action: ("Done", { reordering = false }))
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if project.scenes.count > 1 {
                            SceneOrder(scenes: project.scenes) { store.moveScenes(from: $0, to: $1) }
                        }
                        let shown = sceneFilter.flatMap(scene(for:)) ?? store.currentScene
                        if !shown.shots.isEmpty {
                            OrderList(
                                heading: "Shots in \(shown.name)",
                                renameTitle: "Edit Caption",
                                rows: shown.shots.map {
                                    .init(id: $0.id, number: $0.number, name: $0.caption, detail: "\(Format.mm($0.lensMM))mm")
                                },
                                move: { store.moveShots(in: shown.id, from: $0, to: $1) },
                                rename: { store.setCaption($0, to: $1) }
                            )
                        }
                    }
                }
            }
            .padding(.top, 18)
            .padding(.horizontal, 20)
            .background(Sheet.bg)
            .foregroundStyle(Sheet.text)
            .presentationDetents([.medium, .large])
            .font(.osRow)
        }
        .confirmationDialog(
            "Delete \"\(deletingScene?.name ?? "")\"?",
            isPresented: Binding(get: { deletingScene != nil }, set: { if !$0 { deletingScene = nil } }),
            titleVisibility: .visible,
            presenting: deletingScene
        ) { scene in
            Button("Delete \(scene.name)", role: .destructive) {
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
            #if DEBUG
            // Screenshot testing: -openShot YES opens the latest shot's sheet when upright.
            if UserDefaults.standard.bool(forKey: "openShot") { sheetID = selectedID }
            #endif
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
                    Label("Viewfinder", systemImage: "chevron.left")
                        .font(.osSupport)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                if !visible.isEmpty {
                    // Clears every shot in view: this scene, or all scenes. Asks first.
                    Button("Delete All") { confirmDeleteAll = true }
                        .font(.osSupport)
                        .foregroundStyle(Sheet.muted)
                        .buttonStyle(.plain)
                        .frame(minHeight: 44)
                        .padding(.trailing, Space.s)
                        .confirmationDialog(
                            "Delete \(visible.count == 1 ? "this shot" : "all \(visible.count) shots") in \(sceneFilter.flatMap(scene(for:))?.name ?? "All Scenes")?",
                            isPresented: $confirmDeleteAll,
                            titleVisibility: .visible
                        ) {
                            Button("Delete \(Self.shots(visible.count))", role: .destructive) {
                                store.deleteShots(Set(visible.map(\.shot.id)))
                                selectedID = nil
                            }
                        } message: {
                            Text("The stills go too. This can't be undone.")
                        }
                }
                Button("Projects") {
                    store.showingShotList = false
                    store.panel = .projects
                }
                .font(.osSupport)
                .buttonStyle(.plain)
                .frame(minHeight: 44)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    Text("Shot List · ").font(.osData).foregroundStyle(Sheet.muted)
                    EditableName(text: project.name, font: .osData, color: Sheet.muted, title: "Rename Project") {
                        store.renameProject(project.id, to: $0)
                    }
                }
                if let s = sceneFilter.flatMap(scene(for:)) {
                    EditableName(text: s.name, font: Fonts.mono(22), title: "Rename Scene", pencil: true, pencilSize: 14, inPlace: true) { store.renameScene(s.id, to: $0) }
                } else {
                    Text("All scenes").font(Fonts.mono(22)).lineLimit(1)
                }
                Text(subtitle).font(.osSupport).foregroundStyle(Sheet.muted)
            }

            FadingHScroll {
                // E: plain words, so a clear gap between scenes does the job a pill's edge used to.
                HStack(spacing: Space.l) {
                    let total = project.scenes.reduce(0) { $0 + $1.shots.count }
                    Chip(label: "All Scenes · \(total)", selected: sceneFilter == nil, underline: true) {
                        sceneFilter = nil
                    }
                    ForEach(project.scenes) { s in
                        Chip(label: "\(s.name) · \(s.shots.count)", selected: sceneFilter == s.id, underline: true) {
                            sceneFilter = s.id
                            store.select(project: project.id, scene: s.id)
                        }
                        .contextMenu {
                            // A project always keeps at least one scene.
                            if project.scenes.count > 1 {
                                Button("Rename or Reorder", systemImage: "arrow.left.arrow.right") { reordering = true }
                                Button("Delete Scene", systemImage: "trash", role: .destructive) { deletingScene = s }
                            }
                        }
                    }
                    Chip(label: "+ Scene", underline: true) {
                        store.showingShotList = false
                        store.requestNewScene()
                    }
                }
            }
            if project.scenes.count > 1 || !store.currentScene.shots.isEmpty { sceneHint }

            if visible.isEmpty {
                Text("No shots in this scene yet. Pin one from the viewfinder and it lands here.")
                    .font(.osSupport)
                    .foregroundStyle(Sheet.muted)
                    .padding(.top, Space.m)
                Spacer()
            } else {
                // The day's sun stays put above the shots as they scroll.
                SunPathStrip(shots: visible.map(\.shot), selected: selected?.shot, height: 40) { selectedID = $0.id }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visible) { item in
                            ShotRow(shot: item.shot, sceneName: sceneFilter == nil ? item.scene.name : nil, selected: item.shot.id == selected?.shot.id)
                                .onTapGesture { selectedID = item.shot.id }
                                .swipeToDelete {
                                    selectedID = item.shot.id
                                    confirmDelete = true
                                }
                                // Press and hold a shot to delete it; it still asks first.
                                .contextMenu {
                                    Button("Delete \(item.shot.number)", systemImage: "trash", role: .destructive) {
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
                    EditableName(text: project.name, font: .osData, color: Sheet.muted, title: "Rename Project") {
                        store.renameProject(project.id, to: $0)
                    }
                    Spacer()
                    Text(Format.time(Date())).font(.osNum).foregroundStyle(Sheet.muted)
                }
                EditableName(text: s.name, font: Fonts.mono(22), title: "Rename Scene", pencil: true, pencilSize: 14, inPlace: true) { store.renameScene(s.id, to: $0) }
                Text([s.note, Self.shots(s.shots.count)].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.osData).foregroundStyle(Sheet.muted).lineLimit(1)
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
                                Text("\(sc.shots.count)").font(.osNum).opacity(0.6)
                            }
                            .font(.osData)
                            .foregroundStyle(on ? Sheet.bg : Sheet.text)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(on ? Sheet.text : .clear, in: Capsule())
                            .overlay(Capsule().strokeBorder(on ? Sheet.text : Sheet.rule, lineWidth: 1))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            // A project always keeps at least one scene.
                            if project.scenes.count > 1 {
                                Button("Rename or Reorder", systemImage: "arrow.left.arrow.right") { reordering = true }
                                Button("Delete Scene", systemImage: "trash", role: .destructive) { deletingScene = sc }
                            }
                        }
                    }
                }
                .padding(.horizontal, Space.l)
            }
            .scrollIndicators(.hidden)
            .padding(.bottom, project.scenes.count > 1 ? 6 : 12)

            if project.scenes.count > 1 || !store.currentScene.shots.isEmpty { sceneHint.padding(.horizontal, Space.l).padding(.bottom, 10) }

            if !s.shots.isEmpty {
                SunPathStrip(shots: s.shots, selected: s.shots.first { $0.id == selectedID } ?? s.shots.last, height: 64) {
                    selectedID = $0.id
                    sheetID = $0.id
                }
                .padding(.horizontal, Space.l)
                .padding(.bottom, 12)
            }

            Rule()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(s.shots) { shot in
                        PortraitShotRow(shot: shot)
                            .onTapGesture {
                                selectedID = shot.id
                                sheetID = shot.id
                            }
                            .swipeToDelete {
                                selectedID = shot.id
                                confirmDelete = true
                            }
                            // Press and hold a shot to delete it; it still asks first.
                            .contextMenu {
                                Button("Delete \(shot.number)", systemImage: "trash", role: .destructive) {
                                    selectedID = shot.id
                                    confirmDelete = true
                                }
                            }
                    }
                    if s.shots.isEmpty {
                        Text("No shots in this scene yet.")
                            .font(.osRow)
                            .foregroundStyle(Sheet.muted)
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
                        Text("Viewfinder")
                    }
                    .font(.osTitle)
                    .foregroundStyle(Sheet.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .overlay(Capsule().strokeBorder(Sheet.text, lineWidth: 1))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                Button { store.showingExport = true } label: {
                    Text("Export")
                        .font(.osTitle)
                        .foregroundStyle(Sheet.bg)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Sheet.text, in: Capsule())
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
                Button("Delete \(store.shot(id)?.number ?? "Shot")", role: .destructive) {
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
                Color.black.opacity(0.55).ignoresSafeArea()
                    .onTapGesture { sheetID = nil }
                    .transition(.opacity)

                VStack(alignment: .leading, spacing: 14) {
                    // A visible way out, as well as tapping above or swiping down.
                    HStack {
                        Text("Shot \(shot.number)").font(.osRow)
                        Spacer()
                        Button("Done") { sheetID = nil }
                            .buttonStyle(.plain)
                            .font(.osRow)
                            .frame(minWidth: 44, minHeight: 32, alignment: .trailing)
                            .contentShape(Rectangle())
                    }
                    .padding(.bottom, -6)

                    ShotThumb(shot: shot)
                        .frame(maxWidth: .infinity)
                        .frame(height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(alignment: .bottomLeading) {
                            Text("\(shot.number) · \(Format.mm(shot.lensMM))mm · \(Format.time(shot.plannedTime))")
                                .font(.osNumSmall)
                                .foregroundStyle(Sheet.text.opacity(0.8))
                                .padding(.leading, 10)
                                .padding(.bottom, 8)
                        }
                        .onTapGesture { enlarged = shot }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("tap to see it full screen")

                    Text(shot.caption.isEmpty ? "Untitled" : shot.caption)
                        .font(Fonts.mono(15))
                        .foregroundStyle(shot.caption.isEmpty ? Sheet.muted : Sheet.text)
                        .lineLimit(3)

                    EditableName(text: shot.notes ?? "", font: .osData, color: Sheet.text, lineLimit: 2,
                                 emptyLabel: "Notes: access, power, practicals, sound", title: "Notes", pencil: true) {
                        store.setNotes(id, to: $0)
                    }

                    HStack(alignment: .top, spacing: Space.xs) {
                        sheetCell("Lens", "\(Format.mm(shot.lensMM))mm")
                        sheetCell("Time", Format.time(shot.plannedTime))
                        sheetCell("Light", shot.light.label)
                        if let read = shot.lightRead ?? shot.sunSide { sheetCell("Sun", read) }
                    }

                    HStack(spacing: Space.xs) {
                        Button {
                            store.rename = RenameRequest(title: "Edit Caption", text: shot.caption) { [store] in
                                store.setCaption(id, to: $0)
                            }
                        } label: {
                            Text("Edit Caption")
                                .font(.osRow)
                                .foregroundStyle(Sheet.text)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .overlay(Capsule().strokeBorder(Sheet.rule, lineWidth: 1))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        Button {
                            sheetID = nil
                            reframe(shot)
                        } label: {
                            Text("Reframe")
                                .font(.osRow)
                                .foregroundStyle(Sheet.bg)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Sheet.text, in: Capsule())
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
                        .fill(Sheet.bg)
                        .ignoresSafeArea()
                )
                .foregroundStyle(Sheet.text)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 20).onEnded { v in
                        if v.translation.height > 80 { sheetID = nil }
                    }
                )
                .transition(.move(edge: .bottom))
            }
        }
    }

    /// Tells people the scene chips can be held.
    private var sceneHint: some View {
        Button { reordering = true } label: {
            Text("Hold a scene to delete it · tap here to rename or reorder")
                .font(.osDataSmall)
                .foregroundStyle(Sheet.muted)
        }
        .buttonStyle(.plain)
    }

    private func sheetCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).foregroundStyle(Sheet.muted)
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
                        // A tap anywhere on the picture opens it full screen; the corner icon says so.
                        .overlay(alignment: .bottomTrailing) {
                            Button { enlarged = shot } label: {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Sheet.text)
                                    .frame(width: 24, height: 24)
                                    .background(Color.black.opacity(0.45))
                                    .padding(4)
                                    .frame(width: 44, height: 44, alignment: .bottomTrailing)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("view full screen")
                        }
                        .onTapGesture { enlarged = shot }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("tap to see it full screen")

                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text("\(shot.number) · \(shot.aspect.display) · \(Format.mm(shot.lensMM))mm · \(Format.time(shot.plannedTime))")
                            .font(.osNum)
                            .foregroundStyle(Sheet.muted)
                        // Tap the caption to rewrite it; the export uses whatever's here.
                        EditableName(text: shot.caption, font: .osTitle, lineLimit: 3, emptyLabel: "Untitled", title: "Edit Caption", pencil: true) {
                            store.setCaption(shot.id, to: $0)
                        }
                        .id(shot.id)
                        HStack(spacing: 0) {
                            EditableName(text: item.scene.name, font: .osSupport, color: Sheet.muted, title: "Rename Scene", pencil: true) {
                                store.renameScene(item.scene.id, to: $0)
                            }
                            Text(" · \(shot.cameraName)").font(.osSupport).foregroundStyle(Sheet.muted)
                        }
                        if let loc = shot.location {
                            Text(loc.display).font(.osData).foregroundStyle(Sheet.muted).lineLimit(2)
                        }
                        // Printed on the Detailed PDF's card.
                        EditableName(text: shot.notes ?? "", font: .osData, color: Sheet.text, lineLimit: 2,
                                     emptyLabel: "Notes: access, power, practicals, sound", title: "Notes", pencil: true) {
                            store.setNotes(shot.id, to: $0)
                        }
                        .id("notes" + shot.id.uuidString)
                    }
                }

                Rule()
                HStack(spacing: 0) {
                    readout("Lens", "\(Format.mm(shot.lensMM))mm")
                    readout("Time", Format.time(shot.plannedTime))
                    readout("Light", shot.light.label, golden: shot.isGolden)
                    readout("Light read", shot.lightRead ?? "–")
                    readout("Sun", "\(Int(shot.sunAzimuth.rounded()))° / \(Int(shot.sunElevation.rounded()))°")
                }
                Rule()

                // Frame lines can be changed after the shot; "full" shows the whole frame.
                FadingHScroll {
                    HStack(spacing: Space.xxs) {
                        HStack(spacing: 4) {
                            Text("Frame lines")
                            Image(systemName: "pencil").font(.system(size: 9)).accessibilityHidden(true)
                        }
                        .font(.osDataSmall).foregroundStyle(Sheet.muted)
                        .padding(.trailing, Space.xxs)
                        ForEach([AspectRatio.full(shot.stillAspect ?? AspectRatio.viewfinderValue)] + store.aspectStrip) { a in
                            Chip(label: a.display, selected: a.label == shot.aspect.label, underline: true) {
                                store.setShotAspect(shot.id, to: a)
                            }
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Space.xs) {
                    Button("Delete") { confirmDelete = true }
                        .buttonStyle(PillButtonStyle(kind: .text))
                    Button("Reframe") { reframe(shot) }
                        .buttonStyle(PillButtonStyle(kind: .text))
                    Spacer()
                    Button("Export List") { store.showingExport = true }
                        .buttonStyle(PillButtonStyle(kind: .outline))
                        .frame(maxWidth: 200)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.l)
            .confirmationDialog("Delete \(shot.number)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete \(shot.number)", role: .destructive) {
                    store.deleteShot(shot.id)
                    selectedID = nil
                }
            }
        } else {
            VStack(spacing: Space.m) {
                Spacer()
                Text("Pin a shot from the viewfinder to see it here.")
                    .font(.osSupport)
                    .foregroundStyle(Sheet.muted)
                Spacer()
            }
        }
    }

    static func shots(_ n: Int) -> String { n == 1 ? "1 shot" : "\(n) shots" }

    private func readout(_ label: String, _ value: String, golden: Bool? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.osDataSmall).foregroundStyle(Sheet.muted)
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

/// E1 row: number, caption, lens and time on one ruled line. The picked row is bright,
/// the rest grey; a golden-hour time is the one orange thing.
struct ShotRow: View {
    let shot: Shot
    var sceneName: String?
    let selected: Bool

    var body: some View {
        HStack(spacing: Space.s) {
            Text(shot.number)
                .font(.osNum)
                .foregroundStyle(Sheet.muted)
                .frame(width: 34, alignment: .leading)
            (Text(sceneName.map { "\($0) · " } ?? "").foregroundStyle(Sheet.muted)
                + Text(shot.caption.isEmpty ? "Untitled" : shot.caption))
                .font(.osRow)
                .foregroundStyle(selected ? Sheet.text : Sheet.muted)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(Format.mm(shot.lensMM))mm")
                .font(.osNum)
                .foregroundStyle(Sheet.muted)
                .frame(width: 46, alignment: .trailing)
            Text(Format.time(shot.plannedTime))
                .font(.osNum)
                .foregroundStyle(shot.isGolden ? Palette.sun : Sheet.muted)
                .frame(width: 40, alignment: .trailing)
        }
        .frame(height: 34)
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
                (Text(shot.number).font(.osNum).foregroundStyle(Sheet.muted)
                    + Text(" " + (shot.caption.isEmpty ? "Untitled" : shot.caption)))
                    .font(Fonts.mono(13))
                    .lineLimit(1)
                Text(["\(Format.mm(shot.lensMM))mm", Format.time(shot.plannedTime), shot.light.label, shot.lightRead ?? shot.sunSide].compactMap { $0 }.joined(separator: " · "))
                    .font(.osData)
                    .foregroundStyle(Sheet.muted)
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
    @Environment(ScoutStore.self) private var store
    let shot: Shot
    let onClose: () -> Void
    @State private var saving = false

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
                Text("\(shot.number) · \(shot.caption.isEmpty ? "Untitled" : shot.caption) · \(Format.mm(shot.lensMM))mm · \(shot.aspect.display)")
                    .font(.osData)
                    .foregroundStyle(Sheet.text)
                    .padding(.horizontal, Space.xs)
                    .padding(.vertical, Space.xxs + 1)
                    .background(Palette.hud, in: RoundedRectangle(cornerRadius: Radius.readout))
                    .padding(.bottom, Space.s)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onClose)
        // Tapping anywhere closes it; the X makes that obvious.
        .overlay(alignment: .topTrailing) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Sheet.text)
                .frame(width: 36, height: 36)
                .background(Palette.hud, in: Circle())
                .padding(Space.s)
                .allowsHitTesting(false)
        }
        // Save just this still to Photos, cropped to its frame lines.
        .overlay(alignment: .bottomTrailing) {
            Button {
                saving = true
                Task {
                    do {
                        try await PhotoSaver.save([shot])
                        store.toast = "Saved \(shot.number) to Photos"
                    } catch {
                        store.toast = "Couldn't save to Photos. Check access in Settings."
                    }
                    saving = false
                }
            } label: {
                Label("Save to Photos", systemImage: "square.and.arrow.down")
                    .font(.osData)
                    .foregroundStyle(Sheet.text)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(Palette.hud, in: Capsule())
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(saving)
            .padding(Space.s)
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("close full screen")
    }
}
