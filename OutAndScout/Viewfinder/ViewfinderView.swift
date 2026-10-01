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
                    .frame(width: 52)

                VStack(spacing: Space.xs) {
                    TopBar(heading: location.heading, sunAzimuth: sun.azimuth)
                        .frame(height: 44)

                    // Always 16:9, like a monitor; frame lines for the chosen ratio sit inside it.
                    ViewfinderFrame(sun: sun, sunDay: sunDay, planned: planned, frameFraction: $frameFraction)
                        .aspectRatio(AspectRatio.viewfinderValue, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.viewfinder, style: .continuous))

                    BottomBar(sunDay: sunDay, planned: planned, sun: sun)
                        .frame(height: 44)
                }

                RightRail(capturing: capturing) {
                    Task { await pin() }
                }
                .frame(width: 92)
            }
            .padding(.vertical, Space.xs)
            // The keyboard slides over the viewfinder rather than shoving it off the top.
            .ignoresSafeArea(.keyboard)

            overlays
        }
        // The keyboard only ever slides over the app; nothing gets pushed up or squashed.
        .ignoresSafeArea(.keyboard)
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
        // Keep the whole 16:9 frame; the frame lines are applied when the shot is shown or
        // exported, so they can be changed afterwards.
        let photo = await camera.capturePhoto(aspect: AspectRatio.viewfinderValue, frameFraction: 1)

        let planned = store.plannedDate()
        let coord = location.coordinate
        let sun = SunCalculator.position(at: planned, latitude: coord.latitude, longitude: coord.longitude)
        let comps = Calendar.current.dateComponents([.hour, .minute], from: planned)
        let hour = Double(comps.hour ?? 12) + Double(comps.minute ?? 0) / 60
        let light = LightPhase.from(elevation: sun.elevation, localHour: hour)

        var sunInFrame = false
        if let heading = location.heading, sun.elevation > -2 {
            let hfov = store.kit.horizontalFOV(focal: lens)
            sunInFrame = abs(Bearing.difference(sun.azimuth, heading)) < hfov / 2
                && abs(sun.elevation - motion.cameraElevation) < hfov / store.aspect.value / 2
        }

        async let labels = VisionLabels.labels(for: photo)
        async let place = location.shotLocation()

        let suggestions = Captioner.suggestions(
            lensMM: lens,
            sensorWidthMM: store.kit.mode.widthMM * store.kit.lenses.squeeze,
            labels: await labels,
            light: light,
            sunInFrame: sunInFrame
        )

        store.pending = PendingShot(
            number: number,
            photo: photo,
            suggestions: suggestions,
            lensMM: lens,
            plannedTime: planned,
            sun: sun,
            light: light,
            bearing: location.heading,
            location: await place
        )
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
