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
    @Environment(\.isPortrait) private var portrait

    @State private var sunDay: SunDay?
    @State private var frameFraction: Double = 1
    @State private var capturing = false

    var body: some View {
        let planned = store.plannedDate()
        let coord = location.coordinate
        let sun = SunCalculator.position(at: planned, latitude: coord.latitude, longitude: coord.longitude)

        ZStack {
            Palette.night.ignoresSafeArea()

            Group {
                if portrait {
                    portraitLayout(sun: sun, planned: planned)
                } else {
                    landscapeLayout(sun: sun, planned: planned)
                }
            }
            // While the screen turns, the viewfinder steps back to black and fades in on the new
            // layout, so you never see one layout stretched into the other.
            .opacity(LayoutMode.shared.turning ? 0 : 1)

            if let metres = movedMetres {
                SceneChangeChip(metres: metres) { newScene in
                    keptScenes.insert(store.currentSceneID)
                    if newScene { store.requestNewScene() }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, chipTop)
                .padding(.horizontal, portrait ? Space.m : 0)
                .transition(.opacity)
            } else if let id = store.justSaved, let shot = store.shot(id) {
                SavedChip(shot: shot)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, chipTop)
                    .padding(.horizontal, portrait ? Space.m : 0)
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
        .onChange(of: portrait) {
            updateHeadingOrientation()
            fitAspectToLayout()
        }
        .onAppear {
            updateHeadingOrientation()
            fitAspectToLayout()
        }
    }

    /// The landscape ratio to go back to after portrait, kept across launches.
    private static let landscapeAspectKey = "landscapeAspect"

    /// Upright, a wide ratio would leave most of the screen empty, so start on 9:16 unless a
    /// tall or square ratio (or the full frame) is already picked. Whenever the
    /// screen is sideways again, the ratio you had comes back.
    private func fitAspectToLayout() {
        let a = store.aspect
        let defaults = UserDefaults.standard
        if portrait {
            // Any wide ratio (16:9 included) starts upright as 9:16; pick 16:9 again if you want it.
            if !a.isFull && a.value > 1.01 {
                defaults.set(try? JSONEncoder().encode(a), forKey: Self.landscapeAspectKey)
                store.setAspect(.vertical)
            }
        } else if let data = defaults.data(forKey: Self.landscapeAspectKey),
                  let back = try? JSONDecoder().decode(AspectRatio.self, from: data) {
            defaults.removeObject(forKey: Self.landscapeAspectKey)
            if PortraitToolsRow.ratios.contains(where: { $0.label == a.label && $0.value < 1.5 }) {
                store.setAspect(back)
            }
        }
    }

    /// Chips sit just under the top bar in landscape; upright, just inside the frame.
    private var chipTop: CGFloat { portrait ? 92 : 52 }

    /// Upright, top to bottom: names, clock and kit; + scene, compass and the layout
    /// switch; the frame; toggles and ratios; time over the sun timeline; shots, shutter, lens.
    private func portraitLayout(sun: SunPosition, planned: Date) -> some View {
        VStack(spacing: 0) {
            PortraitTopRow(planned: planned)
                .padding(.horizontal, Space.m)
                .frame(height: 44)

            PortraitCompassRow(
                heading: motion.heading ?? location.heading,
                headingAccuracy: location.headingAccuracy,
                sunAzimuth: sun.azimuth
            )
            .padding(.horizontal, Space.m)
            .frame(height: 36)

            ViewfinderFrame(sun: sun, sunDay: sunDay, planned: planned, frameFraction: $frameFraction, portrait: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .padding(.top, 4)

            PortraitToolsRow()
                .padding(.horizontal, Space.m)
                .frame(height: 44)

            PortraitTimeRow(sunDay: sunDay, planned: planned, sun: sun)
                .padding(.horizontal, Space.l)
                .padding(.top, 4)

            PortraitBottomRow(capturing: capturing) {
                Task { await pin() }
            }
            .frame(height: 92)
            .padding(.top, 4)
        }
        .ignoresSafeArea(.keyboard)
    }

    /// E2 layout: the viewfinder fills the whole screen and every control floats over it,
    /// with soft shade at the top, bottom and right edges so the type stays readable.
    /// Taps that miss a control fall through to the viewfinder (focus, pinch, AE/AF lock).
    private func landscapeLayout(sun: SunPosition, planned: Date) -> some View {
        // HUD D, "Framed" (Elliot, 6 Oct 2026): the picture lives in one fixed window, the
        // ratio frame always fitted whole inside it and everything outside the frame dark,
        // so you know exactly what's in shot. The controls sit on ink around the window,
        // never over the picture.
        VStack(spacing: 0) {
            TopBar(
                heading: motion.heading ?? location.heading,
                headingAccuracy: location.headingAccuracy,
                sunAzimuth: sun.azimuth,
                planned: planned
            )
            .frame(height: 44)
            // Lines "Projects" up over the left column and the names over the window.
            .padding(.leading, Space.s)
            .padding(.trailing, Space.m)

            HStack(spacing: Space.s) {
                LeftRail()
                    .frame(width: 64)
                    .padding(.leading, Space.s)

                VStack(spacing: 0) {
                    ViewfinderFrame(sun: sun, sunDay: sunDay, planned: planned, frameFraction: $frameFraction)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        // The window's edge: a hairline, square.
                        .overlay(Rectangle().strokeBorder(Sheet.rule, lineWidth: 1))

                    BottomBar(sunDay: sunDay, planned: planned, sun: sun)
                        .frame(height: 52)
                }

                RightRail(capturing: capturing) {
                    Task { await pin() }
                }
                .frame(width: 104)
                .padding(.trailing, Space.m)
            }
        }
        .padding(.vertical, Space.xs)
        .background(Sheet.bg.ignoresSafeArea())
        // The keyboard slides over the viewfinder rather than shoving it off the top.
        .ignoresSafeArea(.keyboard)
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
                // Tap anywhere else to close the name bar (the name stays as it is).
                Color.black.opacity(0.001).ignoresSafeArea()
                    .onTapGesture { store.namingSceneID = nil }
                NameSceneCard().transition(.move(edge: .top).combined(with: .opacity))
            } else if store.showingCustomAspect {
                CustomAspectCard().transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: cardIsOpen)
    }

    /// Scenes where "keep" was picked, so the new-scene question isn't asked again there.
    @State private var keptScenes: Set<UUID> = []

    /// How far you've walked from this scene's last shot, once it's more than 100 m. GPS has to be good to
    /// within 30 m, or a poor fix could fake the move.
    private var movedMetres: Int? {
        guard !cardIsOpen, store.justSaved == nil, !keptScenes.contains(store.currentSceneID),
              let here = location.location, here.horizontalAccuracy >= 0, here.horizontalAccuracy < 30,
              let last = store.currentScene.shots.last(where: { $0.location != nil })?.location
        else { return nil }
        let d = here.distance(from: CLLocation(latitude: last.latitude, longitude: last.longitude))
        return d > 100 ? Int((d / 10).rounded() * 10) : nil
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
        let stillAspect = ViewfinderFrame.sensorAspect(kit: store.kit, aspect: store.aspect, portrait: portrait)
        let photo = await camera.capturePhoto(aspect: stillAspect, frameFraction: frameFraction)

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
            / (ViewfinderFrame.sensorOnSide(aspect: store.aspect, portrait: portrait) ? store.kit.frameAspect : 1)
        // The caption and the place name arrive separately: outdoors with a weak signal the
        // street lookup can take ages, and the caption used to sit on "Captioning…" until it did.
        Task {
            let seen = await VisionLabels.see(photo)
            let suggestions = Captioner.suggestions(
                lensMM: lens,
                sensorWidthMM: sensorWidth,
                seen: seen,
                light: light,
                sunInFrame: sunInFrame
            )
            // Never leave it blank: fall back to the light if Vision saw nothing usable.
            store.fillIn(shot.id, caption: suggestions.first?.text ?? light.label, location: nil)
        }
        Task {
            let place = await location.shotLocation()
            store.fillIn(shot.id, caption: nil, location: place)
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

/// "● 5A · lamp, night  [edit]" for a few seconds after the shutter, a paper pill at the
/// top like the v3c prototype. The caption fills in when it's ready; tap to change it.
private struct SavedChip: View {
    @Environment(ScoutStore.self) private var store
    let shot: Shot

    var body: some View {
        Button {
            store.justSaved = nil
            store.rename = RenameRequest(title: "Caption \(shot.number)", text: shot.caption) { [store, id = shot.id] in
                store.setCaption(id, to: $0)
            }
        } label: {
            HStack(spacing: 10) {
                Circle().fill(Palette.sun).frame(width: 7, height: 7)
                Text("\(shot.number) · \(shot.caption.isEmpty ? "Captioning…" : shot.caption)")
                    .lineLimit(1)
                Text("Edit")
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Palette.paper, in: Capsule())
            }
            .font(.osData)
            .foregroundStyle(Palette.paper)
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .frame(height: 36)
            // Translucent over the live image, so the scene shows through behind the caption.
            .background(Palette.ink.opacity(0.72), in: Capsule())
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.paper.opacity(0.14), lineWidth: 1))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 440)
        .accessibilityLabel("edit caption for shot \(shot.number)")
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
        HStack(spacing: 10) {
            Image(systemName: "location").font(.system(size: 11))
            Text("Moved \(metres) m · new scene?").lineLimit(1).minimumScaleFactor(0.8)
            Button("Keep") { choose(false) }
                .padding(.horizontal, 12)
                .frame(height: 32)
                .overlay(Capsule().strokeBorder(Palette.rule, lineWidth: 1))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            Button("New Scene") { choose(true) }
                .foregroundStyle(Palette.paper)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Palette.ink, in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .font(.osData)
        .foregroundStyle(Palette.ink)
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .frame(height: 40)
        .background(Palette.paper, in: Capsule())
    }
}
