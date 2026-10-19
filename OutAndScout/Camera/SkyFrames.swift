import AVFoundation
import CoreVideo

/// One camera frame read for the sky sweep: for each of a row of columns across the
/// picture, how far down the sky goes.
struct SkyColumns: Sendable {
    /// Per column, left to right: where the sky ends as a fraction of the picture's height
    /// from the top. nil when the top of the column isn't sky (something taller than the
    /// frame); 1 when it's sky all the way down.
    var edges: [Double?]
    /// The picture's width over its height, as delivered (already turned upright).
    var aspect: Double
}

/// Reads frames while a sweep runs. Looking along the sun's path the sky is the bright part
/// and roofs and trees stand dark against it, so a column's sky ends where it first gets
/// clearly darker than the sky above it.
final class SkyFrameReader: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let handler: @Sendable (SkyColumns) -> Void
    private var count = 0

    init(handler: @escaping @Sendable (SkyColumns) -> Void) {
        self.handler = handler
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Ten reads a second is plenty for a slow pan.
        count += 1
        guard count % 3 == 0, let pb = CMSampleBufferGetImageBuffer(sampleBuffer),
              let cols = Self.read(pb) else { return }
        handler(cols)
    }

    static let columns = 48
    private static let rows = 64

    static func read(_ pb: CVPixelBuffer) -> SkyColumns? {
        guard CVPixelBufferGetPixelFormatType(pb) == kCVPixelFormatType_32BGRA else { return nil }
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)
        let stride = CVPixelBufferGetBytesPerRow(pb)
        guard w > columns * 2, h > rows * 2 else { return nil }
        let px = base.assumingMemoryBound(to: UInt8.self)

        // A coarse grid of brightness, each cell the average of a few pixels.
        let cw = w / columns, rh = h / rows
        var grid = [[Double]](repeating: [Double](repeating: 0, count: rows), count: columns)
        for c in 0..<columns {
            for r in 0..<rows {
                var sum = 0.0
                for (dx, dy) in [(1, 1), (3, 1), (1, 3), (3, 3)] {
                    let x = c * cw + cw * dx / 4, y = r * rh + rh * dy / 4
                    let o = y * stride + x * 4
                    let b = Double(px[o]), g = Double(px[o + 1]), red = Double(px[o + 2])
                    sum += 0.114 * b + 0.587 * g + 0.299 * red
                }
                grid[c][r] = sum / 4
            }
        }

        // How bright the sky is: most of the top row should be sky on a sweep.
        let top = grid.map { $0[0] }.sorted()
        let sky = top[Int(Double(top.count - 1) * 0.8)]
        // Too dark to tell sky from roof (after dusk, or a hand over the lens).
        guard sky > 50 else { return nil }

        var edges: [Double?] = []
        for c in 0..<columns {
            let col = grid[c]
            let ref = min(col[0], sky)
            let line = ref * 0.62
            guard col[0] >= sky * 0.62 else { edges.append(nil); continue }
            var edge = 1.0
            for r in 1..<rows where col[r] < line && (r + 1 == rows || col[r + 1] < line) {
                edge = Double(r) / Double(rows)
                break
            }
            edges.append(edge)
        }
        return SkyColumns(edges: edges, aspect: Double(w) / Double(h))
    }
}
