import SwiftUI

@main
struct OutAndScoutApp: App {
    @State private var store = ScoutStore()
    @State private var camera = CameraController()
    @State private var location = LocationService()
    @State private var motion = MotionService()

    init() {
        Fonts.registerBundled()
    }

    var body: some SwiftUI.Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(camera)
                .environment(location)
                .environment(motion)
        }
    }
}

/// The Viewfinder is the dashboard. Everything else slides over it.
struct RootView: View {
    @Environment(ScoutStore.self) private var store
    @Environment(CameraController.self) private var camera
    @Environment(LocationService.self) private var location
    @Environment(MotionService.self) private var motion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            ViewfinderView()

            if store.showingShotList {
                ShotListView()
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
            }

            if let toast = store.toast {
                Text(toast)
                    .font(.osData)
                    .foregroundStyle(Palette.paper)
                    .padding(.horizontal, Space.s)
                    .padding(.vertical, Space.xs)
                    .background(Palette.hud, in: Capsule())
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, Space.xs)
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
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .task {
            await camera.start()
            location.start()
            motion.start()
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
