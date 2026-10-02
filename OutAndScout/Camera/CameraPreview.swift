import AVFoundation
import SwiftUI
import UIKit

/// Live camera preview. Keeps the image level using the rotation coordinator.
///
/// The preview layer is made once and reused. Each time this view appears (a layout
/// switch builds a new viewfinder) the same layer is moved into the new spot, so the
/// running capture session never has to hook up a fresh preview. Doing that froze the
/// screen for seconds after every portrait / landscape switch.
struct CameraPreview: UIViewRepresentable {
    let camera: CameraController

    @MainActor private static var shared: PreviewView?

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = UIColor(Palette.night)
        container.clipsToBounds = true
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        let view = Self.sharedView(for: camera)
        if view.superview !== container {
            view.removeFromSuperview()
            view.frame = container.bounds
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            container.addSubview(view)
        }
        if view.coordinator == nil, let device = camera.device {
            view.attach(device: device, camera: camera)
        }
    }

    @MainActor private static func sharedView(for camera: CameraController) -> PreviewView {
        if let shared { return shared }
        let view = PreviewView()
        view.previewLayer.session = camera.session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = UIColor(Palette.night)
        camera.previewLayer = view.previewLayer
        shared = view
        return view
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        fileprivate(set) var coordinator: AVCaptureDevice.RotationCoordinator?
        private var previewObservation: NSKeyValueObservation?
        private var captureObservation: NSKeyValueObservation?

        func attach(device: AVCaptureDevice, camera: CameraController) {
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
            self.coordinator = coordinator

            previewObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] c, _ in
                let angle = c.videoRotationAngleForHorizonLevelPreview
                DispatchQueue.main.async {
                    guard let connection = self?.previewLayer.connection else { return }
                    if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
                    if connection.isVideoStabilizationSupported {
                        connection.preferredVideoStabilizationMode = .previewOptimized
                    }
                }
            }
            captureObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.initial, .new]) { [weak camera] c, _ in
                let angle = c.videoRotationAngleForHorizonLevelCapture
                DispatchQueue.main.async { camera?.captureRotationAngle = angle }
            }
        }
    }
}
