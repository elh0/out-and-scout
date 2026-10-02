import CoreLocation
import CoreMotion
import Observation

/// Where the back camera points, from Core Motion's fused attitude (gyro + accelerometer +
/// compass). Steadier than the raw compass heading, which wobbles, and it doesn't care which
/// way up the phone is held. Also how far off level the phone is, for the level.
@MainActor
@Observable
final class MotionService {
    /// Degrees above the horizon the back camera points. 0 = level, 90 = straight up.
    private(set) var cameraElevation: Double = 0
    /// Degrees from north the back camera faces (true north when location is allowed).
    /// nil until the attitude settles, or when the phone points nearly straight up or down.
    private(set) var heading: Double?
    /// Degrees of roll away from level in landscape.
    private(set) var roll: Double = 0

    private let manager = CMMotionManager()
    private var frame: CMAttitudeReferenceFrame?

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        // True north needs location permission; fall back to magnetic north without it.
        let status = CLLocationManager().authorizationStatus
        let allowed = status == .authorizedWhenInUse || status == .authorizedAlways
        let available = CMMotionManager.availableAttitudeReferenceFrames()
        let wanted: CMAttitudeReferenceFrame = allowed && available.contains(.xTrueNorthZVertical) ? .xTrueNorthZVertical : .xMagneticNorthZVertical
        if manager.isDeviceMotionActive {
            guard wanted != frame else { return }
            manager.stopDeviceMotionUpdates()
        }
        frame = wanted
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(using: wanted, to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let g = motion.gravity
            // The back camera looks along the device's -z axis. Its angle above the horizon is
            // asin(g.z) with gravity as a unit vector.
            let elevation = asin(max(-1, min(1, g.z))) * 180 / .pi
            // In landscape, gravity lies along ±x when level; any y component is roll.
            let roll = atan2(g.y, abs(g.x)) * 180 / .pi * (g.x < 0 ? 1 : -1)
            let azimuth = Self.cameraAzimuth(motion.attitude.rotationMatrix, gravity: g)
            MainActor.assumeIsolated {
                self.cameraElevation = elevation
                self.roll = roll
                if let azimuth, abs(elevation) < 80 {
                    // Light smoothing on the circle so 359° → 1° doesn't swing through 180°.
                    if let h = self.heading {
                        let delta = Bearing.difference(azimuth, h)
                        self.heading = (h + delta * 0.35 + 360).truncatingRemainder(dividingBy: 360)
                    } else {
                        self.heading = azimuth
                    }
                } else {
                    self.heading = nil
                }
            }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }

    /// The reference frame's axes (x = north, y = west, z = up) expressed in device
    /// coordinates. Whether they sit in the matrix's rows or columns is checked against
    /// gravity rather than assumed: the up axis must point opposite gravity.
    nonisolated static func cameraAzimuth(_ m: CMRotationMatrix, gravity g: CMAcceleration) -> Double? {
        let columns = (north: (m.m11, m.m21, m.m31), west: (m.m12, m.m22, m.m32), up: (m.m13, m.m23, m.m33))
        let rows = (north: (m.m11, m.m12, m.m13), west: (m.m21, m.m22, m.m23), up: (m.m31, m.m32, m.m33))
        let dotUp = { (u: (Double, Double, Double)) in -(u.0 * g.x + u.1 * g.y + u.2 * g.z) }
        let axes = dotUp(columns.up) >= dotUp(rows.up) ? columns : rows
        // Camera direction is device -z, so its north and west components are -north.z and -west.z.
        let n = -axes.north.2
        let w = -axes.west.2
        guard n * n + w * w > 0.0004 else { return nil }
        let az = atan2(-w, n) * 180 / .pi
        return (az + 360).truncatingRemainder(dividingBy: 360)
    }
}
