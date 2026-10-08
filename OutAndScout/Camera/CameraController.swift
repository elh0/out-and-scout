import AVFoundation
import Observation
import UIKit

/// The camera, set up to look as close to Apple's Camera app as we can get.
///
/// Uses the virtual multi-camera device (triple on Pro phones, dual-wide elsewhere) so the
/// system picks the physical lens nearest the cine focal length and only crops the
/// remainder, rather than digitally cropping a single lens like most scouting apps.
@MainActor
@Observable
final class CameraController: NSObject {
    enum Status { case idle, unauthorized, unavailable, running }

    private(set) var status: Status = .idle
    /// "iphone 1x · 1.9x crop"
    private(set) var readout = ""
    /// Just the live iPhone lens, e.g. "1x". The short form shown under the lens wheel.
    private(set) var lensLabel = ""
    /// True once the digital crop gets big enough to look soft. The readout greys out.
    private(set) var cropIsSoft = false
    /// True when the cine lens sees wider than the phone can, even fully zoomed out.
    private(set) var isTooWide = false
    /// How much bigger the cine frame is than what the phone sees when the lens is too wide
    /// (1 otherwise). The viewfinder shrinks the picture by this, inside the true frame lines.
    private(set) var shrink: Double = 1
    private(set) var aeAfLocked = false
    private(set) var exposureBias: Float = 0
    /// Horizontal field of view of the live preview, degrees.
    private(set) var previewHFOV: Double = 70

    /// Set by the preview from the rotation coordinator, applied to stills.
    @ObservationIgnored var captureRotationAngle: CGFloat = 0
    @ObservationIgnored weak var previewLayer: AVCaptureVideoPreviewLayer?

    nonisolated let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "outandscout.camera")

    @ObservationIgnored private(set) var device: AVCaptureDevice?
    /// Zoom factor at which each physical lens takes over, widest first. [1] for a single lens.
    @ObservationIgnored private var lensFactors: [CGFloat] = [1]
    /// Converts a device zoom factor to the number Apple shows (so the wide lens reads "1x").
    @ObservationIgnored private var displayMultiplier: CGFloat = 1
    /// Horizontal FOV at zoom factor 1.
    /// The camera's long-side field of view at 1×.
    @ObservationIgnored private var longSideFOV: Double = 70
    /// Long side over short side of the camera's frames (4:3 on iPhone).
    @ObservationIgnored private(set) var formatAspect: Double = 4.0 / 3.0
    /// Upright, the preview's width spans the camera's short side.
    @ObservationIgnored var portrait = false
    /// Field of view across the preview's width at 1×.
    private var baseHFOV: Double {
        portrait ? 2 * atan(tan(longSideFOV * .pi / 360) / formatAspect) * 180 / .pi : longSideFOV
    }
    @ObservationIgnored private var configured = false
    @ObservationIgnored private var isStarting = false
    @ObservationIgnored private var inFlight: [Int64: PhotoDelegate] = [:]

    // MARK: Setup

    func start() async {
        // Launch and returning from the permission prompt both call this. Only one may
        // configure the session; a second would fail to add the input and mark it unavailable.
        guard status != .running, !isStarting else { return }
        #if DEBUG
        // Simulator screenshots: -noCamera YES skips the camera and its permission prompt.
        if UserDefaults.standard.bool(forKey: "noCamera") { return }
        #endif
        isStarting = true
        defer { isStarting = false }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { status = .unauthorized; return }
        default:
            status = .unauthorized
            return
        }

        if configured {
            let session = session
            queue.async { if !session.isRunning { session.startRunning() } }
            status = .running
            return
        }

        guard let device = Self.bestBackCamera() else { status = .unavailable; return }
        self.device = device
        readLensInfo(from: device)

        let session = session
        let output = photoOutput
        let ok: Bool = await withCheckedContinuation { cont in
            queue.async {
                session.beginConfiguration()
                session.sessionPreset = .photo
                guard let input = try? AVCaptureDeviceInput(device: device),
                      session.canAddInput(input), session.canAddOutput(output) else {
                    session.commitConfiguration()
                    cont.resume(returning: false)
                    return
                }
                session.addInput(input)
                session.addOutput(output)
                output.maxPhotoQualityPrioritization = .quality
                // 12MP is plenty for a scouting still and keeps capture quick.
                let dims = device.activeFormat.supportedMaxPhotoDimensions
                    .filter { $0.width <= 4032 }
                    .max { $0.width * $0.height < $1.width * $1.height }
                if let dims { output.maxPhotoDimensions = dims }
                session.commitConfiguration()

                Self.applyDefaults(to: device)
                session.startRunning()
                cont.resume(returning: true)
            }
        }
        configured = ok
        // The photo preset switches the camera to its 4:3 photo format; read the field of
        // view again from that, not the start-up format, so the lens matching is true.
        if ok { readLensInfo(from: device) }
        status = ok ? .running : .unavailable
        // Exposure stays where you put it, even after the app is closed.
        let saved = UserDefaults.standard.float(forKey: Self.biasKey)
        if ok, saved != 0 { setExposureBias(saved) }
    }

    func stop() {
        guard status == .running else { return }
        status = .idle
        let session = session
        queue.async { session.stopRunning() }
    }

    private static func bestBackCamera() -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera,
        ]
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .back)
        // DiscoverySession returns devices in the order of `types`.
        return discovery.devices.first
    }

    private nonisolated static func applyDefaults(to device: AVCaptureDevice) {
        guard (try? device.lockForConfiguration()) != nil else { return }
        defer { device.unlockForConfiguration() }
        if device.isLowLightBoostSupported {
            device.automaticallyEnablesLowLightBoostWhenAvailable = true
        }
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        if device.activeFormat.isVideoHDRSupported { device.automaticallyAdjustsVideoHDREnabled = true }
        device.isSubjectAreaChangeMonitoringEnabled = true
    }

    private func readLensInfo(from device: AVCaptureDevice) {
        let switches = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat($0.doubleValue) }
        lensFactors = [1] + switches
        let constituents = device.isVirtualDevice ? device.constituentDevices : [device]
        let hasUltraWide = constituents.first?.deviceType == .builtInUltraWideCamera
        displayMultiplier = hasUltraWide && !switches.isEmpty ? 1 / switches[0] : 1
        longSideFOV = Double(device.activeFormat.videoFieldOfView)
        let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        if dims.width > 0, dims.height > 0 {
            formatAspect = Double(max(dims.width, dims.height)) / Double(min(dims.width, dims.height))
        }
        previewHFOV = baseHFOV
    }

    // MARK: Matching the cine lens

    /// Zooms so the frame lines show what `targetHFOV` degrees would see.
    /// `frameFraction` is the frame-line width divided by the preview width.
    func match(targetHFOV: Double, frameFraction: Double) {
        guard let device else { return }
        let rad = { (d: Double) in d * .pi / 180 }
        let wanted = tan(rad(baseHFOV) / 2) * frameFraction / tan(rad(targetHFOV) / 2)
        let minZoom = device.minAvailableVideoZoomFactor
        let maxZoom = min(device.maxAvailableVideoZoomFactor, lensFactors.last! * 10)
        let z = min(max(CGFloat(wanted), minZoom), maxZoom)

        let session = session
        queue.async {
            guard session.isRunning, (try? device.lockForConfiguration()) != nil else { return }
            device.ramp(toVideoZoomFactor: z, withRate: 32)
            device.unlockForConfiguration()
        }

        previewHFOV = 2 * atan(tan(rad(baseHFOV) / 2) / Double(z)) * 180 / .pi
        isTooWide = CGFloat(wanted) < minZoom - 0.01
        shrink = isTooWide ? Double(minZoom) / wanted : 1
        updateReadout(zoom: z, tooWide: isTooWide)
    }

    /// The widest view, in degrees, that a frame spanning `frameFraction` of the preview's
    /// width can show with the phone fully zoomed out.
    func widestHFOV(frameFraction: Double) -> Double {
        let zMin = Double(device?.minAvailableVideoZoomFactor ?? 1)
        return 2 * atan(tan(baseHFOV * .pi / 360) * frameFraction / zMin) * 180 / .pi
    }

    private func updateReadout(zoom z: CGFloat, tooWide: Bool) {
        let i = lensFactors.lastIndex { $0 <= z + 0.001 } ?? 0
        let lens = lensFactors[i] * displayMultiplier
        let crop = z / lensFactors[i]
        let lensText = "iphone " + Self.format(lens) + "x"
        // Like the Camera app: the overall zoom, 0.5×, 1×, 1.9×, 3×.
        lensLabel = Self.format(z * displayMultiplier) + "×"
        if tooWide {
            readout = lensText + " · wider than the iphone sees"
            cropIsSoft = true
        } else if crop < 1.05 {
            readout = lensText
            cropIsSoft = false
        } else {
            readout = lensText + " · " + Self.format(crop) + "x crop"
            cropIsSoft = crop > 2.5
        }
    }

    private static func format(_ x: CGFloat) -> String {
        let r = (x * 10).rounded() / 10
        return r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)
    }

    // MARK: Focus and exposure

    private static let biasKey = "exposureBias"

    /// Tap: focus and expose on a point, keep adjusting.
    func focus(atLayerPoint point: CGPoint) {
        guard let device, let layer = previewLayer else { return }
        let p = layer.captureDevicePointConverted(fromLayerPoint: point)
        aeAfLocked = false
        // Keep the exposure offset; tapping only moves where the camera meters.
        let bias = exposureBias
        queue.async {
            guard (try? device.lockForConfiguration()) != nil else { return }
            defer { device.unlockForConfiguration() }
            if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = p }
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = p }
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            device.setExposureTargetBias(bias)
        }
    }

    /// Long press: focus and expose once, then hold (AE/AF lock).
    func lock(atLayerPoint point: CGPoint) {
        guard let device, let layer = previewLayer else { return }
        let p = layer.captureDevicePointConverted(fromLayerPoint: point)
        aeAfLocked = true
        queue.async {
            guard (try? device.lockForConfiguration()) != nil else { return }
            defer { device.unlockForConfiguration() }
            if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = p }
            if device.isFocusModeSupported(.autoFocus) { device.focusMode = .autoFocus }
            if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = p }
            if device.isExposureModeSupported(.autoExpose) { device.exposureMode = .autoExpose }
        }
    }

    /// The sun slider. -2...+2 stops, clamped to what the device allows.
    func setExposureBias(_ value: Float) {
        guard let device else { return }
        let v = min(max(value, device.minExposureTargetBias), device.maxExposureTargetBias)
        exposureBias = v
        UserDefaults.standard.set(v, forKey: Self.biasKey)
        queue.async {
            guard (try? device.lockForConfiguration()) != nil else { return }
            device.setExposureTargetBias(v)
            device.unlockForConfiguration()
        }
    }

    // MARK: Stills

    /// Takes a quality-prioritised still and crops it to the frame lines.
    func capturePhoto(aspect: Double, frameFraction: Double) async -> Data? {
        guard status == .running, session.isRunning,
              photoOutput.connection(with: .video)?.isActive == true else { return nil }

        let settings: AVCapturePhotoSettings
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        } else {
            settings = AVCapturePhotoSettings()
        }
        // Balanced keeps the shutter quick; .quality waits on heavy multi-frame processing.
        settings.photoQualityPrioritization = .balanced
        settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
        if let connection = photoOutput.connection(with: .video),
           connection.isVideoRotationAngleSupported(captureRotationAngle) {
            connection.videoRotationAngle = captureRotationAngle
        }

        let id = settings.uniqueID
        let raw: Data? = await withCheckedContinuation { cont in
            let delegate = PhotoDelegate { data in cont.resume(returning: data) }
            inFlight[id] = delegate
            photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
        inFlight[id] = nil

        guard let raw else { return nil }
        return await Task.detached(priority: .userInitiated) {
            StillCropper.crop(raw, aspect: aspect, widthFraction: frameFraction) ?? raw
        }.value
    }
}

/// Bridges the photo delegate callback to async/await.
private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private var completion: ((Data?) -> Void)?

    init(completion: @escaping (Data?) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        completion?(error == nil ? photo.fileDataRepresentation() : nil)
        completion = nil
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        // Covers the case where processing never delivered a photo.
        completion?(nil)
        completion = nil
    }
}

enum StillCropper {
    /// Crops an upright still to the centred frame lines and re-encodes it.
    static func crop(_ data: Data, aspect: Double, widthFraction: Double) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        var w = size.width * min(max(widthFraction, 0.05), 1)
        var h = w / aspect
        if h > size.height {
            h = size.height
            w = h * aspect
        }
        let rect = CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let out = UIGraphicsImageRenderer(size: rect.size, format: format).image { _ in
            image.draw(at: CGPoint(x: -rect.minX, y: -rect.minY))
        }
        return out.heicData() ?? out.jpegData(compressionQuality: 0.9)
    }
}
