import CoreLocation
import Combine
import SwiftUI

/// 01 Viewfinder. Dark, landscape, the dashboard for everything.
///
/// Top bar: project / scene, + scene, compass tape, kit chip.
/// Left rail: sun path, grid, level. Right rail: lens wheel, shutter, shot stack.
/// Bottom: aspect strip, time + light, sun timeline.
struct ViewfinderView: View {
    @Environment(ScoutStore.self) private var store
    @Environment(CameraController.self) private var camera
    @Environment(LocationService.self) private var location
    @Environment(MotionService.self) private var motion

    @State private var sunDay: SunDay?
    @State private var frameFraction: Double = 1
    @State private var capturing = false

    var body: some View {
        let planned = store.plannedDate()
        let coord = location.coordinate
        let sun = SunCalculator.position(at: planned, latitude: coord.latitude, longitude: coord.longitude)

        ZStack {
            Palette.night.ignoresSafeArea()

            HStack(spacing: Space.xs) {
                LeftRail()
                    .frame(width: 88)

                VStack(spacing: Space.xs) {
                    TopBar(heading: (motion.heading ?? location.heading), sunAzimuth: sun.azimuth)
                        .frame(height: 44)

                    // Always 16:9, like a monitor; frame lines for the chosen ratio sit inside it.
                    ViewfinderFrame(sun: sun, sunDay: sunDay, planned: planned, frameFraction: $frameFraction)
                        .aspectRatio(store.kit.frameAspect, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.viewfinder, style: .continuous))

                    BottomBar(sunDay: sunDay, planned: planned, sun: sun)
                        .frame(height: 44)
                }

                RightRail(capturing: capturing) {
                    Task { await pin() }
                }
                .frame(width: 80)
            }
            .padding(.vertical, Space.xs)
            // The keyboard slides over the viewfinder rather than shoving it off the top.
            .ignoresSafeArea(.keyboard)

            if let metres = movedMetres {
                SceneChangeChip(metres: metres) { newScene in
                    keptScenes.insert(store.currentSceneID)
                    if newScene { store.requestNewScene() }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 52 + Space.xs)
                .transition(.opacity)
            } else if let id = store.justSaved, let shot = store.shot(id) {
                SavedChip(shot: shot)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 52 + Space.xs)
                    .transition(.opacity)
                    .id(id)
            }

            overlays
        }
        // The keyboard only ever slides over the app; nothing gets pushed up or squashed.
        .ignoresSafeArea(.keyboard)
        .animation(.easeOut(duration: 0.2), value: store.justSaved)
        // Switch the compass to true north once location is allowed.
        .onChange(of: location.authorization) { motion.start() }
        .task(id: DayKey(date: planned, latitude: coord.latitude, longitude: coord.longitude)) {
            let day = await Task.detached(priority: .utility) {
                SunCalculator.day(containing: planned, latitude: coord.latitude, longitude: coord.longitude)
            }.value
            sunDay = day
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            updateHeadingOrientation()
        }
        .onAppear(perform: updateHeadingOrientation)
    }

    // MARK: Overlays (cards and panels slide over the Viewfinder, never replace it)

    @ViewBuilder private var overlays: some View {
        // Panels
        ZStack {
            if store.panel != nil {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { store.panel = nil }
                    .transition(.opacity)
            }
            if store.panel == .projects {
                ProjectsPanel()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.move(edge: .leading))
            }
            if store.panel == .kit {
                KitPanel()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.snappy(duration: 0.28), value: store.panel)

        // Cards
        ZStack {
            // The name bar is light-touch, so the image stays undimmed behind it.
            if cardIsOpen && store.namingSceneID == nil {
                Color.black.opacity(0.45).ignoresSafeArea().transition(.opacity)
            }
            if store.pending != nil {
                CaptionCard().transition(.move(edge: .bottom).combined(with: .opacity))
            } else if store.askingLocation {
                LocationPermissionCard().transition(.move(edge: .bottom).combined(with: .opacity))
            } else if store.namingSceneID != nil {
                NameSceneCard().transition(.move(edge: .top).combined(with: .opacity))
            } else if store.showingCustomAspect {
                CustomAspectCard().transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: cardIsOpen)
    }

    /// Scenes where "keep" was picked, so the new-scene question isn't asked again there.
    @State private var keptScenes: Set<UUID> = []

    /// How far you've walked from this scene's last shot, once it's more than 300 m.
    private var movedMetres: Int? {
        guard !cardIsOpen, store.justSaved == nil, !keptScenes.contains(store.currentSceneID),
              let here = location.location, here.horizontalAccuracy >= 0, here.horizontalAccuracy < 100,
              let last = store.currentScene.shots.last(where: { $0.location != nil })?.location
        else { return nil }
        let d = here.distance(from: CLLocation(latitude: last.latitude, longitude: last.longitude))
        return d > 300 ? Int((d / 10).rounded() * 10) : nil
    }

    private var cardIsOpen: Bool {
        store.pending != nil || store.askingLocation || store.namingSceneID != nil || store.showingCustomAspect
    }

    // MARK: Pinning

    /// Every pin is a shot: take the still, work out the sun and light, suggest captions.
    private func pin() async {
        guard !capturing, store.pending == nil else { return }
        capturing = true
        defer { capturing = false }

        let number = store.nextShotNumber
        let lens = store.lensMM
        // Keep the whole sensor-mode frame; the frame lines are applied when the shot is shown
        // or exported, so they can be changed afterwards.
        let stillAspect = store.kit.frameAspect
        let photo = await camera.capturePhoto(aspect: stillAspect, frameFraction: 1)

        let planned = store.plannedDate()
        let coord = location.coordinate
        let sun = SunCalculator.position(at: planned, latitude: coord.latitude, longitude: coord.longitude)
        let comps = Calendar.current.dateComponents([.hour, .minute], from: planned)
        let hour = Double(comps.hour ?? 12) + Double(comps.minute ?? 0) / 60
        let light = LightPhase.from(elevation: sun.elevation, localHour: hour)

        var sunInFrame = false
        if let heading = (motion.heading ?? location.heading), sun.elevation > -2 {
            let hfov = store.kit.horizontalFOV(focal: lens)
            sunInFrame = abs(Bearing.difference(sun.azimuth, heading)) < hfov / 2
                && abs(sun.elevation - motion.cameraElevation) < hfov / (store.aspect.isFull ? stillAspect : store.aspect.value) / 2
        }

        let shot = PendingShot(
            number: number,
            photo: photo,
            suggestions: [],
            lensMM: lens,
            plannedTime: planned,
            sun: sun,
            light: light,
            bearing: (motion.heading ?? location.heading),
            location: nil,
            stillAspect: stillAspect
        )
        // Save now so the shutter is ready again at once; the caption and place name
        // arrive in the background and can be edited later in the Shot List.
        store.addShot(shot, caption: "")
        store.toast = nil
        store.justSaved = shot.id

        let sensorWidth = store.kit.mode.widthMM * store.kit.lenses.squeeze
        Task {
            async let seen = VisionLabels.see(photo)
            async let place = location.shotLocation()
            let suggestions = Captioner.suggestions(
                lensMM: lens,
                sensorWidthMM: sensorWidth,
                seen: await seen,
                light: light,
                sunInFrame: sunInFrame
            )
            store.fillIn(shot.id, caption: suggestions.first?.text, location: await place)
        }
    }

    private func updateHeadingOrientation() {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        if let orientation = scene?.effectiveGeometry.interfaceOrientation {
            location.setInterfaceOrientation(orientation)
        }
    }

    private struct DayKey: Hashable {
        var day: Int
        var lat: Int
        var lon: Int
        init(date: Date, latitude: Double, longitude: Double) {
            day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
            // Recompute when you move more than ~1km.
            lat = Int((latitude * 100).rounded())
            lon = Int((longitude * 100).rounded())
        }
    }
}

enum Bearing {
    /// Signed smallest difference a - b in degrees, -180...180.
    static func difference(_ a: Double, _ b: Double) -> Double {
        var d = (a - b).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }
}

/// "5A · lamp, night   edit" for a few seconds after the shutter. The caption fills in when
/// it's ready; tap edit to change it in the name bar.
private struct SavedChip: View {
    @Environment(ScoutStore.self) private var store
    let shot: Shot

    var body: some View {
        HStack(spacing: Space.s) {
            Text("\(shot.number) · \(shot.caption.isEmpty ? "captioning…" : shot.caption)")
                .font(.osData)
                .foregroundStyle(Palette.paper)
                .lineLimit(1)
            Button("edit") {
                store.justSaved = nil
                store.rename = RenameRequest(title: "caption \(shot.number)", text: shot.caption) { [store, id = shot.id] in
                    store.setCaption(id, to: $0)
                }
            }
            .font(.osData)
            .foregroundStyle(Palette.nightMuted)
            .underline()
            .frame(minHeight: 44)
        }
        .padding(.horizontal, Space.s)
        .background(Palette.hud, in: Capsule())
        .frame(maxWidth: 420)
        .task {
            guard (try? await Task.sleep(for: .seconds(4))) != nil else { return }
            if store.justSaved == shot.id { store.justSaved = nil }
        }
    }
}

/// "moved 340 m · new scene?" with keep / new scene, after you walk away from the last shot.
private struct SceneChangeChip: View {
    let metres: Int
    let choose: (Bool) -> Void

    var body: some View {
        HStack(spacing: Space.s) {
            Text("moved \(metres) m · new scene?")
                .font(.osData)
                .foregroundStyle(Palette.paper)
                .lineLimit(1)
            Button("keep") { choose(false) }
                .foregroundStyle(Palette.nightMuted)
                .frame(minHeight: 44)
            Button("new scene") { choose(true) }
                .foregroundStyle(Palette.paper)
                .underline()
                .frame(minHeight: 44)
        }
        .font(.osData)
        .padding(.horizontal, Space.s)
        .background(Palette.hud, in: Capsule())
    }
}
