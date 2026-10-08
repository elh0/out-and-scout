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
    @State private var sheetDeletingScene: ScoutScene?
    /// The shot shown full screen, for holding the phone up to a director.
    @State private var enlarged: Shot?
    /// The shot opened in place in the list.
    @State private var openID: UUID?
    @Environment(\.isPortrait) private var portrait
    /// The two-week forecast for the scene in view.
    @State private var showingWeather = false

    var body: some View {
        ZStack {
            Sheet.bg.ignoresSafeArea()

            Group {
                if portrait { portraitOutline } else { landscapeList }
            }
            .foregroundStyle(Sheet.text)
            .confirmationDialog("Delete shot \(selected?.shot.number ?? "")?", isPresented: $confirmDelete, titleVisibility: .visible, presenting: selected?.shot) { shot in
                Button("Delete \(shot.number)", role: .destructive) {
                    store.deleteShot(shot.id)
                    if openID == shot.id { openID = nil }
                    selectedID = nil
                }
            } message: { _ in
                Text("Its still goes too. This can't be undone.")
            }

            ZStack {
                if store.showingExport {
                    // v3c: rgba(17,17,17,0.45) behind the panel; tap it to close.
                    Color.black.opacity(0.55).ignoresSafeArea()
                        .onTapGesture { store.showingExport = false }
                        .transition(.opacity)
                    // Round 4: a card centred over the list, just inside the screen's edges.
                    ExportPanel(scene: sceneFilter.flatMap(scene(for:)))
                        .frame(maxWidth: portrait ? .infinity : 1000, maxHeight: portrait ? .infinity : 720)
                        .padding(.horizontal, portrait ? 12 : 18)
                        .padding(.vertical, portrait ? 8 : 14)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
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
        .sheet(isPresented: $reordering) {
            let project = store.currentProject
            VStack(alignment: .leading, spacing: 16) {
                PanelHeader(title: "Edit Scenes", sub: "Tap a name to rename, drag to reorder. Exports follow this order.", action: ("Done", { reordering = false }))
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Project").font(.osDataSmall).foregroundStyle(Sheet.muted)
                            EditableName(text: project.name, font: .osRow, emptyLabel: "Untitled", title: "Rename Project", fillsWidth: true, pencil: true) {
                                store.renameProject(project.id, to: $0)
                            }
                            .frame(height: 40)
                            .overlay(alignment: .bottom) { Rule() }
                        }
                        if project.scenes.count > 1 {
                            SceneOrder(scenes: project.scenes, move: { store.moveScenes(from: $0, to: $1) }) { id in
                                sheetDeletingScene = project.scenes.first { $0.id == id }
                            }
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
                        if !visible.isEmpty {
                            // Clears every shot in view: this scene, or all scenes. Asks first.
                            Button("Delete all \(Self.shots(visible.count)) in \(sceneFilter.flatMap(scene(for:))?.name ?? "All Scenes")") { confirmDeleteAll = true }
                                .font(.osDataSmall)
                                .foregroundStyle(Self.warning)
                                .buttonStyle(.plain)
                                .frame(minHeight: 44)
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
                    }
                }
            }
            .padding(.top, 18)
            .padding(.horizontal, 20)
            .background(Sheet.bg)
            .foregroundStyle(Sheet.text)
            .presentationDetents([.medium, .large])
            .font(.osRow)
            .renameBar()
            // A dialog on the screen behind can't show over this sheet, so it has its own.
            .confirmationDialog(
                "Delete \"\(sheetDeletingScene?.name ?? "")\"?",
                isPresented: Binding(get: { sheetDeletingScene != nil }, set: { if !$0 { sheetDeletingScene = nil } }),
                titleVisibility: .visible,
                presenting: sheetDeletingScene
            ) { scene in
                Button("Delete \(scene.name)", role: .destructive) {
                    if sceneFilter == scene.id { sceneFilter = nil }
                    store.deleteScene(scene.id)
                    selectedID = nil
                    sheetDeletingScene = nil
                }
            } message: { scene in
                Text("Its \(Self.shots(scene.shots.count)) go too, stills included. This can't be undone.")
            }
        }
        .sheet(isPresented: $showingWeather) {
            let sc = sceneFilter.flatMap(scene(for:)) ?? store.currentScene
            if let place = Exporter.place(of: sc) {
                ForecastSheet(sceneName: sc.name, place: place, shots: sc.shots) { showingWeather = false }
                    .presentationDetents([.medium, .large])
            } else {
                VStack(alignment: .leading, spacing: Space.s) {
                    PanelHeader(title: "Weather · \(sc.name)", sub: "No location saved for this scene yet.", action: ("Done", { showingWeather = false }))
                    Text("Pin a shot here first; its spot is used for the forecast.").font(.osRow).foregroundStyle(Sheet.muted)
                    Spacer()
                }
                .padding(.top, 18).padding(.horizontal, 20)
                .background(Sheet.bg).foregroundStyle(Sheet.text)
                .presentationDetents([.medium])
            }
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
            openID = selectedID
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

    // MARK: Outline look, round 4 (locked 8 Oct 2026)

    /// Landscape: Projects, "PROJECT / SHOT LIST", Weather and Export along the top; the
    /// scenes on the left with "← Camera" at the bottom; the day's arc with every shot on it,
    /// then calm rows. Tap a row to open it in place, again to close.
    private var landscapeList: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 4) {
                    EditableName(text: project.name, font: Fonts.mono(11), color: Sheet.text, title: "Rename Project") {
                        store.renameProject(project.id, to: $0)
                    }
                    Text("/ SHOT LIST").font(Fonts.mono(11)).tracking(0.6).foregroundStyle(Sheet.muted).fixedSize()
                }
                .padding(.horizontal, 190)
                HStack(spacing: 8) {
                    Button {
                        store.showingShotList = false
                        store.panel = .projects
                    } label: {
                        Text("Projects").font(Fonts.mono(11)).frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    OPill(label: "Weather", caps: true) { showingWeather = true }
                    OPill(label: "Export", on: true, caps: true) { store.showingExport = true }
                        .disabled(visible.isEmpty)
                }
            }
            .frame(height: 44)

            HStack(alignment: .top, spacing: Space.m) {
                sceneColumn
                    .frame(width: 104)
                VStack(alignment: .leading, spacing: 6) {
                    ShotArc(shots: visible.map(\.shot), selected: openID) { openID = $0.id; selectedID = $0.id }
                        .frame(height: 44)
                    HStack {
                        Text("\(Self.shots(visible.count))".uppercased())
                        Spacer()
                        Text("TAP A SHOT TO OPEN · AGAIN TO CLOSE")
                    }
                    .font(Fonts.mono(9)).tracking(0.6).foregroundStyle(Sheet.muted)
                    rows(wide: true)
                }
            }
        }
        .padding(.horizontal, Space.l)
    }

    /// SCENES: All, each scene with its count, Edit; "← Camera" at the bottom.
    private var sceneColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SCENES").font(Fonts.mono(10)).tracking(0.6).foregroundStyle(Sheet.muted).padding(.bottom, 4)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    filterButton("All · \(project.scenes.reduce(0) { $0 + $1.shots.count })", on: sceneFilter == nil) { sceneFilter = nil }
                    ForEach(project.scenes) { sc in
                        filterButton("\(sc.name) · \(sc.shots.count)", on: sceneFilter == sc.id) {
                            sceneFilter = sc.id
                            store.select(project: project.id, scene: sc.id)
                        }
                        .contextMenu {
                            Button("Edit Scenes", systemImage: "arrow.up.arrow.down") { reordering = true }
                            if project.scenes.count > 1 {
                                Button("Delete Scene", systemImage: "trash", role: .destructive) { deletingScene = sc }
                            }
                        }
                    }
                    Button { reordering = true } label: {
                        Text("Edit").font(Fonts.mono(10)).foregroundStyle(Sheet.muted)
                            .underline(color: Sheet.rule)
                            .frame(minHeight: 32).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("edit scenes: rename, reorder, delete")
                }
            }
            Spacer(minLength: Space.s)
            Button { store.showingShotList = false } label: {
                Text("← Camera").font(Fonts.mono(11)).underline(color: Sheet.text)
                    .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, Space.xs)
    }

    private func filterButton(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Fonts.mono(10))
                .foregroundStyle(on ? Sheet.text : Sheet.muted)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Upright: Camera and Weather / Export on top, the project, scene pills, the arc, rows.
    private var portraitOutline: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button { store.showingShotList = false } label: {
                    Text("← Camera").font(Fonts.mono(11)).frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                OPill(label: "Edit", caps: true) { reordering = true }
                OPill(label: "Weather", caps: true) { showingWeather = true }
                OPill(label: "Export", on: true, caps: true) { store.showingExport = true }
                    .disabled(visible.isEmpty)
            }
            EditableName(text: project.name, font: .osSans(22), color: Sheet.text, title: "Rename Project", pencil: true) {
                store.renameProject(project.id, to: $0)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    OPill(label: "All · \(project.scenes.reduce(0) { $0 + $1.shots.count })", on: sceneFilter == nil, size: .small) { sceneFilter = nil }
                    ForEach(project.scenes) { sc in
                        OPill(label: "\(sc.name) · \(sc.shots.count)", on: sceneFilter == sc.id, size: .small) {
                            sceneFilter = sc.id
                            store.select(project: project.id, scene: sc.id)
                        }
                    }
                }
            }
            ShotArc(shots: visible.map(\.shot), selected: openID) { openID = $0.id; selectedID = $0.id }
                .frame(height: 44)
            rows(wide: false)
        }
        .padding(.horizontal, Space.l)
    }

    // MARK: Rows

    private func rows(wide: Bool) -> some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    if visible.isEmpty {
                        Text("NO SHOTS YET. PRESS THE SHUTTER ON THE CAMERA.")
                            .font(Fonts.mono(10)).tracking(0.6).foregroundStyle(Sheet.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 14)
                    }
                    ForEach(visible) { item in
                        row(item, wide: wide).id(item.id)
                    }
                    Color.clear.frame(height: 30)
                }
            }
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.9), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            .onChange(of: openID) {
                if let id = openID { withAnimation(.snappy(duration: 0.25)) { proxy.scrollTo(id, anchor: .top) } }
            }
        }
    }

    private func row(_ item: Item, wide: Bool) -> some View {
        let shot = item.shot
        let open = openID == shot.id
        return HStack(alignment: .top, spacing: 14) {
            ShotThumb(shot: shot)
                .frame(width: open ? 128 : 52, height: open ? 72 : 30)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(open ? Sheet.text : Sheet.rule, lineWidth: 1))
                .onTapGesture { if open { enlarged = shot } else { toggle(shot) } }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(open ? "see it full screen" : "open")
            Text(shot.number).font(Fonts.mono(11)).foregroundStyle(Sheet.text).frame(width: 26, alignment: .leading).padding(.top, 3)

            VStack(alignment: .leading, spacing: 3) {
                if open {
                    EditableName(text: shot.caption, font: .osSans(13), color: Sheet.text, lineLimit: 3, emptyLabel: "Untitled", title: "Edit Caption", pencil: true) {
                        store.setCaption(shot.id, to: $0)
                    }
                    .id("cap" + shot.id.uuidString)
                } else {
                    Text(shot.caption.isEmpty ? "Untitled" : shot.caption).font(.osSans(13)).foregroundStyle(Sheet.text).lineLimit(1)
                }
                Text("\(item.scene.name) · \(Format.mm(shot.lensMM))mm".uppercased())
                    .font(Fonts.mono(9)).tracking(0.6).foregroundStyle(Sheet.muted).lineLimit(1)
                if !wide {
                    Text("\(Format.time(shot.plannedTime)) · \(shortRead(shot))".uppercased())
                        .font(Fonts.mono(9)).tracking(0.6).foregroundStyle(shot.isGolden ? Palette.sun : Sheet.muted)
                }
                if open { openDetails(item) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if wide {
                Text(Format.time(shot.plannedTime)).font(Fonts.mono(10))
                    .foregroundStyle(shot.isGolden ? Palette.sun : (open ? Sheet.text : Sheet.muted))
                    .frame(width: 42, alignment: .leading).padding(.top, 3)
                Text(shortRead(shot).uppercased()).font(Fonts.mono(10)).tracking(0.4).foregroundStyle(Sheet.text)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .frame(width: 124, alignment: .leading).padding(.top, 3)
            }
            Text(open ? "–" : "+").font(Fonts.mono(13)).foregroundStyle(Sheet.muted).frame(width: 14).padding(.top, 1)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .top) { Sheet.rule.frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture { toggle(shot) }
        .contextMenu {
            Button("Delete \(shot.number)", systemImage: "trash", role: .destructive) {
                selectedID = shot.id
                confirmDelete = true
            }
        }
        .animation(.snappy(duration: 0.22), value: open)
    }

    /// The opened shot: the light in words, its best time, notes, frame lines, Delete.
    private func openDetails(_ item: Item) -> some View {
        let shot = item.shot
        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(longRead(shot)).font(.osSans(13)).foregroundStyle(Sheet.text)
                if let best = bestTime(shot) {
                    Text("BEST TIME · \(best)".uppercased()).font(Fonts.mono(9)).tracking(0.6).foregroundStyle(Sheet.text)
                }
            }
            .padding(.top, 6)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Notes").font(.osSans(12)).foregroundStyle(Sheet.muted)
                EditableName(text: shot.notes ?? "", font: .osSans(12), color: Sheet.text, lineLimit: 4,
                             emptyLabel: "Access, power, parking", title: "Notes", pencil: true) {
                    store.setNotes(shot.id, to: $0)
                }
                .id("notes" + shot.id.uuidString)
            }
            // Frame lines can change after the shot; "Full" shows the whole frame.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach([AspectRatio.full(shot.stillAspect ?? AspectRatio.viewfinderValue)] + store.aspectStrip) { a in
                        OPill(label: a.display, on: a.label == shot.aspect.label, size: .small) {
                            store.setShotAspect(shot.id, to: a)
                        }
                    }
                }
            }
            Button {
                selectedID = shot.id
                confirmDelete = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash").font(.system(size: 11))
                    Text("Delete shot")
                }
                .font(Fonts.mono(10))
                .foregroundStyle(Self.warning)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .overlay(Capsule().strokeBorder(Self.warning.opacity(0.5), lineWidth: 1))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("delete shot \(shot.number)")
        }
    }

    private func toggle(_ shot: Shot) {
        withAnimation(.snappy(duration: 0.22)) {
            openID = openID == shot.id ? nil : shot.id
            selectedID = shot.id
        }
    }

    /// "Side lit · left", "Sun down", or the old light phase without a heading.
    private func shortRead(_ s: Shot) -> String {
        guard s.sunElevation > -1 else { return "Sun down" }
        guard let b = s.bearing else { return s.light.label }
        return LightClass.readShort(rel: LightRead.rel(sunAzimuth: s.sunAzimuth, heading: b))
    }

    private func longRead(_ s: Shot) -> String {
        guard s.sunElevation > -1 else { return "Sun down at \(Format.time(s.plannedTime))" }
        guard let b = s.bearing else { return s.light.label + ", no compass heading saved" }
        return LightClass.readLong(rel: LightRead.rel(sunAzimuth: s.sunAzimuth, heading: b))
    }

    /// "17:58–18:38, golden hour, ¾ back"
    private func bestTime(_ s: Shot) -> String? {
        guard let b = s.bearing, let loc = s.location else { return nil }
        let day = SunCalculator.day(containing: s.capturedAt, latitude: loc.latitude, longitude: loc.longitude)
        guard let best = LightRead.best(day: day, heading: b) else { return nil }
        return "\(Format.time(best.start))–\(Format.time(best.end)), \(best.why)"
    }

    /// The one red: things that can't be undone.
    static let warning = Color(hex: 0xE5534B)

    static func shots(_ n: Int) -> String { n == 1 ? "1 shot" : "\(n) shots" }
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
