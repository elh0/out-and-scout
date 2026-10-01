import CoreMotion
import Observation

/// Tilt from the accelerometer: where the camera points vertically (for the sun path) and
/// how far off level the phone is held (for the level).
@MainActor
@Observable
final class MotionService {
    /// Degrees above the horizon the back camera points. 0 = level, 90 = straight up.
    private(set) var cameraElevation: Double = 0
    /// Degrees of roll away from level in landscape.
    private(set) var roll: Double = 0

    private let manager = CMMotionManager()

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let g = motion?.gravity else { return }
            // The back camera looks along the device's -z axis. Its angle above the horizon is
            // asin(g.z) with gravity as a unit vector.
            let elevation = asin(max(-1, min(1, g.z))) * 180 / .pi
            // In landscape, gravity lies along ±x when level; any y component is roll.
            let roll = atan2(g.y, abs(g.x)) * 180 / .pi * (g.x < 0 ? 1 : -1)
            MainActor.assumeIsolated {
                self.cameraElevation = elevation
                self.roll = roll
            }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}
