import SwiftUI

@main
struct OutAndScoutApp: App {
    @State private var store = ScoutStore()
    @State private var camera = CameraController()
    @State private var location = LocationService()
    @State private var motion = MotionService()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Fonts.registerBundled()
    }

    var body: some SwiftUI.Scene {
        WindowGroup {
            KeyboardProofHost {
                RootView()
                    .environment(store)
                    .environment(camera)
                    .environment(location)
                    .environment(motion)
            }
            .ignoresSafeArea()
            .statusBarHidden()
            .persistentSystemOverlays(.hidden)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await camera.start() }
                motion.start()
            case .background:
                camera.stop()
                motion.stop()
            default: break
            }
        }
    }
}

/// Hosts the app with the keyboard taken out of its safe area. SwiftUI's
/// .ignoresSafeArea(.keyboard) still let the whole screen ride up when a name
/// field took focus; at this level the keyboard simply slides over the top.
struct KeyboardProofHost<Content: View>: UIViewControllerRepresentable {
    @ViewBuilder let content: () -> Content

    func makeUIViewController(context: Context) -> KeyboardProofController<Content> {
        let host = KeyboardProofController(rootView: content())
        host.safeAreaRegions = .container
        host.view.backgroundColor = UIColor(Palette.night)
        return host
    }

    func updateUIViewController(_ host: KeyboardProofController<Content>, context: Context) {
        host.rootView = content()
    }
}

/// Nested inside SwiftUI, this controller doesn't inherit the notch and
/// home-indicator insets, so it tops them up from the window's own.
final class KeyboardProofController<Content: View>: UIHostingController<Content> {
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        guard let window = view.window else { return }
        let want = window.safeAreaInsets
        let current = view.safeAreaInsets
        let extra = additionalSafeAreaInsets
        // What the view gets without our top-up, then whatever's missing from the window's.
        let base = UIEdgeInsets(
            top: current.top - extra.top, left: current.left - extra.left,
            bottom: current.bottom - extra.bottom, right: current.right - extra.right
        )
        let needed = UIEdgeInsets(
            top: max(0, want.top - base.top), left: max(0, want.left - base.left),
            bottom: max(0, want.bottom - base.bottom), right: max(0, want.right - base.right)
        )
        if needed != extra { additionalSafeAreaInsets = needed }
    }
}

extension EnvironmentValues {
    /// The phone is upright, so screens use their portrait layouts.
    @Entry var isPortrait = false
}

/// The Viewfinder is the dashboard. Everything else slides over it.
struct RootView: View {
    @Environment(ScoutStore.self) private var store
    @Environment(CameraController.self) private var camera
    @Environment(LocationService.self) private var location
    @Environment(MotionService.self) private var motion

    var body: some View {
        // Taller than wide: the portrait layouts from the v3c Portrait board.
        GeometryReader { geo in
            let portrait = geo.size.height > geo.size.width
            content(portrait: portrait).environment(\.isPortrait, portrait)
        }
    }

    private func content(portrait: Bool) -> some View {
        ZStack {
            ViewfinderView()

            if store.showingShotList {
                ShotListView()
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
            }

            if let request = store.rename {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { store.rename = nil }
                    .transition(.opacity)
                    .zIndex(3)
                FloatingNameBar(request: request)
                    .id(request.id)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(4)
            }

            if let toast = store.toast {
                HStack(spacing: Space.xs) {
                    Circle().fill(Palette.sun).frame(width: 7, height: 7)
                    Text(toast)
                }
                    .font(.osData)
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, Space.xs)
                    .background(Palette.paper, in: Capsule())
                    .frame(maxHeight: .infinity, alignment: .top)
                    // Over the frame when upright, like the Portrait board.
                    .padding(.top, portrait ? 93 : 52)
                    .transition(.opacity)
                    .zIndex(2)
                    .task(id: toast) {
                        guard (try? await Task.sleep(for: .seconds(1.8))) != nil else { return }
                        store.toast = nil
                    }
            }
        }
        .ignoresSafeArea(.keyboard)
        .animation(.snappy(duration: 0.28), value: store.showingShotList)
        .animation(.easeOut(duration: 0.2), value: store.toast)
        .animation(.snappy(duration: 0.25), value: store.rename?.id)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .task {
            await camera.start()
            location.start()
            motion.start()
            store.askForLocationIfNeverAsked()
            #if DEBUG
            // Screenshot testing: launch with -openPanel kit|projects|shotlist.
            switch UserDefaults.standard.string(forKey: "openPanel") {
            case "kit": store.panel = .kit
            case "projects": store.panel = .projects
            case "shotlist": store.showingShotList = true
            default: break
            }
            // Screenshot testing: -orientation portrait turns the screen upright.
            if UserDefaults.standard.string(forKey: "orientation") == "portrait",
               let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
            }
            #endif
        }
    }
}
