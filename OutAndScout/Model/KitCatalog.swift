import Foundation

// The kit library. Copied from the v2 prototype.
// TODO: every sensor width here must be verified against manufacturer data before launch.
// Cameras without listed modes use a typical width for their format.

struct SensorMode: Codable, Hashable, Identifiable {
    var name: String
    /// Active sensor width in mm. This is what turns a cine focal length into a field of view.
    var widthMM: Double
    /// Width over height of the recorded area, when the name doesn't say ("3:2", "16:9").
    var aspect: Double? = nil
    var id: String { name }

    /// The mode's shape: given, or read from the name, open gate ≈ 1.44, else 16:9.
    var shape: Double {
        if let aspect { return aspect }
        if let match = name.range(of: #"\d+(\.\d+)?:\d+(\.\d+)?"#, options: .regularExpression) {
            let parts = name[match].split(separator: ":").compactMap { Double($0) }
            if parts.count == 2, parts[1] > 0 { return parts[0] / parts[1] }
        }
        if name.lowercased().contains("open gate") { return 1.44 }
        return 16.0 / 9.0
    }
}

struct Camera: Codable, Hashable, Identifiable {
    var brand: String
    var name: String
    /// "S35", "LF", "FF", "VV", "65mm", "MFT", "S16", "35mm film"
    var format: String
    var resolution: String
    var modes: [SensorMode]
    var id: String { "\(brand) \(name)" }
}

struct LensSeries: Codable, Hashable, Identifiable {
    var brand: String
    var name: String
    /// "spherical", "anamorphic 2x · vintage", "zoom"...
    var type: String
    var focals: [Double]
    var isZoom = false
    var id: String { "\(brand) \(name)" }

    var isAnamorphic: Bool { type.contains("anamorphic") }
    /// 2x anamorphics double the horizontal field of view on the same sensor width.
    var squeeze: Double { type.contains("anamorphic 2x") ? 2 : 1 }
}

/// The camera, sensor mode and lens set the viewfinder is simulating.
struct Kit: Codable, Hashable {
    var camera: Camera
    var mode: SensorMode
    var lenses: LensSeries

    /// "alexa 35 · k35"
    var label: String { "\(camera.name) · \(lenses.name)" }

    /// The viewfinder's shape: the whole recorded frame, desqueezed for anamorphics.
    /// Held between 4:3 (the iPhone's own sensor, so the lens maths stays true) and 2.4.
    var frameAspect: Double {
        min(max(mode.shape * lenses.squeeze, 4.0 / 3.0), 2.4)
    }

    /// Horizontal field of view in degrees for a focal length on this kit.
    func horizontalFOV(focal: Double) -> Double {
        let effectiveWidth = mode.widthMM * lenses.squeeze
        return 2 * atan(effectiveWidth / (2 * focal)) * 180 / .pi
    }

    static let `default`: Kit = {
        let camera = KitCatalog.cameras.first { $0.name == "ALEXA 35" } ?? KitCatalog.cameras[0]
        return Kit(
            camera: camera,
            mode: camera.modes[0],
            lenses: KitCatalog.lenses.first { $0.name == "K35" } ?? KitCatalog.lenses[0]
        )
    }()
}

enum KitCatalog {
    private static func typicalWidth(_ format: String) -> Double {
        switch format {
        case "LF": return 36.7
        case "FF": return 36.0
        case "VV": return 40.96
        case "65mm": return 54.12
        case "MFT": return 17.3
        case "S16": return 12.52
        default: return 24.9 // S35 and 35mm 4-perf
        }
    }

    private static func typicalAspect(_ format: String) -> Double? {
        switch format {
        case "S16": return 1.66
        case "35mm film": return 1.33
        default: return nil
        }
    }

    private static func C(_ brand: String, _ name: String, _ format: String, _ res: String, _ modes: [SensorMode]? = nil) -> Camera {
        Camera(
            brand: brand, name: name, format: format, resolution: res,
            modes: modes ?? [SensorMode(name: "\(format) full sensor", widthMM: typicalWidth(format), aspect: typicalAspect(format))]
        )
    }

    private static func M(_ name: String, _ w: Double, _ aspect: Double? = nil) -> SensorMode {
        SensorMode(name: name, widthMM: w, aspect: aspect)
    }

    private static func L(_ brand: String, _ name: String, _ type: String, _ focals: [Double], zoom: Bool = false) -> LensSeries {
        LensSeries(brand: brand, name: name, type: type, focals: focals, isZoom: zoom)
    }

    static let cameras: [Camera] = [
        // Generic formats, for when the exact camera doesn't matter or isn't listed.
        C("Generic", "Super 16", "S16", "film or digital", [
            M("Super 16", 12.52, 1.66), M("Standard 16", 10.26, 1.37), M("S16 cropped 16:9", 12.52, 16.0 / 9.0),
        ]),
        C("Generic", "Super 35", "S35", "digital", [
            M("S35 3:2", 24.89), M("S35 16:9", 24.89), M("S35 4:3 anamorphic", 22.0),
        ]),
        C("Generic", "Full frame", "FF", "digital", [
            M("FF 3:2", 36.0), M("FF 17:9", 36.0), M("FF 2.39:1", 36.0),
        ]),
        C("ARRI", "ALEXA 35", "S35", "4.6K", [
            M("4.6K 3:2 Open Gate", 28.0), M("4.6K 16:9", 28.0), M("4K 16:9", 24.9), M("4K 2:1", 24.9),
            M("3.8K 16:9 UHD", 23.3), M("3.3K 6:5", 20.2), M("3K 1:1", 18.7), M("2.7K 8:9", 16.4), M("2K 16:9 S16", 12.4),
        ]),
        C("ARRI", "ALEXA 35 Xtreme", "S35", "4.6K · up to 660fps", [
            M("4K 16:9 · 330fps · 660 overdrive", 24.88), M("other formats · to confirm", 24.88),
        ]),
        C("ARRI", "ALEXA Mini LF", "LF", "4.5K", [
            M("4.5K LF Open Gate", 36.7), M("4.5K LF 3:2", 36.7), M("4.5K LF 2.39:1", 36.7),
            M("3.8K LF 16:9 UHD", 31.7), M("2.8K LF 1:1", 23.8),
        ]),
        C("ARRI", "ALEXA Mini", "S35", "3.4K", [
            M("3.4K Open Gate", 28.3), M("3.2K 16:9", 26.4), M("2.8K 4:3", 23.8), M("2.8K 16:9", 23.8),
            M("2.8K 6:5 anamorphic", 23.8), M("HD 16:9", 23.8), M("S16 HD 16:9", 13.2),
        ]),
        C("ARRI", "ALEXA LF", "LF", "4.5K"),
        C("ARRI", "ALEXA 65", "65mm", "6.5K"),
        C("ARRI", "AMIRA", "S35", "3.2K"),
        C("ARRI", "ARRICAM LT", "35mm film", "4-perf"),
        C("ARRI", "ARRIFLEX 416", "S16", "film", [M("Super 16", 12.52, 1.66), M("Standard 16", 10.26, 1.37)]),
        C("RED", "V-RAPTOR 8K VV", "VV", "8K"),
        C("RED", "V-RAPTOR [X] 8K VV", "VV", "8K"),
        C("RED", "V-RAPTOR 8K S35", "S35", "8K"),
        C("RED", "KOMODO-X 6K", "S35", "6K"),
        C("RED", "KOMODO 6K", "S35", "6K"),
        C("RED", "MONSTRO 8K VV", "VV", "8K"),
        C("Sony", "VENICE 2 8K", "FF", "8.6K", [
            M("8.6K 3:2 FF", 36.0), M("8.2K 17:9 FF", 34.4), M("8.2K 2.39:1 FF", 34.4),
            M("5.8K 6:5 S35 anamorphic", 24.3), M("5.5K 2.39:1 S35", 23.0),
        ]),
        C("Sony", "VENICE 2 6K", "FF", "6K"),
        C("Sony", "BURANO", "FF", "8.6K"),
        C("Sony", "FX9", "FF", "6K"),
        C("Sony", "FX6", "FF", "4K"),
        C("Sony", "FX3", "FF", "4K"),
        C("Canon", "EOS C700 FF", "FF", "5.9K"),
        C("Canon", "EOS C500 Mark II", "FF", "5.9K"),
        C("Canon", "EOS C400", "FF", "6K"),
        C("Canon", "EOS C300 Mark III", "S35", "4K"),
        C("Canon", "EOS C70", "S35", "4K"),
        C("Blackmagic", "URSA Cine 12K LF", "LF", "12K"),
        C("Blackmagic", "URSA Mini Pro 12K", "S35", "12K"),
        C("Blackmagic", "PYXIS 6K", "FF", "6K"),
        C("Blackmagic", "Cinema Camera 6K", "FF", "6K"),
        C("Blackmagic", "Pocket 6K Pro", "S35", "6K"),
        C("Blackmagic", "Pocket 4K", "MFT", "4K"),
        C("Panavision", "Millennium DXL2", "VV", "8K"),
        C("Panasonic", "VariCam LT", "S35", "4K"),
        C("Panasonic", "Lumix S1H", "FF", "6K"),
        C("DJI", "Ronin 4D 8K", "FF", "8K"),
        C("Freefly", "Ember S5K", "S35", "5K high speed", [M("5K 5:4 full sensor", 23.04)]),
        C("Freefly", "Ember S2.5K", "S35", "2.5K high speed", [M("2.5K 5:4 full sensor", 23.04)]),
        C("Aaton", "XTR Prod", "S16", "film", [M("Super 16", 12.52, 1.66), M("Standard 16", 10.26, 1.37)]),
        C("Aaton", "A-Minima", "S16", "film", [M("Super 16", 12.52, 1.66)]),
        C("Blackmagic", "Pocket Cinema Camera (original)", "S16", "1080p", [M("S16 16:9", 12.48)]),
        C("Digital Bolex", "D16", "S16", "2K", [M("S16 2K", 12.85, 2048.0 / 1152.0)]),
    ]

    static let lenses: [LensSeries] = [
        // Generic sets: every common focal, from very wide (5.5mm, 6mm) to long.
        L("Generic", "Primes · all focals", "spherical", [5.5, 6, 8, 9.5, 10, 12, 14, 16, 18, 21, 24, 25, 28, 32, 35, 40, 50, 65, 75, 85, 100, 135, 150, 200]),
        L("Generic", "Super 16 primes", "spherical · S16", [5.5, 6, 8, 9.5, 12, 16, 25, 35, 50, 85]),
        L("Generic", "Anamorphic 2x", "anamorphic 2x", [25, 32, 40, 50, 75, 100, 135]),
        L("Zeiss", "Ultra 16", "spherical · S16", [6, 8, 9.5, 12, 14, 16, 25, 35, 50, 85]),
        L("Canon", "8–64 S16 zoom", "zoom · S16", [8, 10, 12, 16, 20, 25, 35, 50, 64], zoom: true),
        L("Canon", "K35", "spherical · vintage", [18, 24, 35, 55, 85]),
        L("Canon", "Sumire Prime", "spherical", [14, 20, 24, 35, 50, 85, 135]),
        L("Cooke", "S4/i", "spherical", [18, 25, 32, 40, 50, 75, 100, 135]),
        L("Cooke", "S7/i Full Frame Plus", "spherical", [18, 25, 32, 40, 50, 75, 100, 135]),
        L("Cooke", "Panchro/i Classic FF", "spherical · vintage look", [18, 25, 32, 40, 50, 75, 100, 135]),
        L("Cooke", "Speed Panchro", "spherical · vintage", [18, 25, 32, 40, 50, 75]),
        L("Cooke", "Anamorphic/i SF", "anamorphic 2x", [32, 40, 50, 75, 100]),
        L("Zeiss", "Super Speed", "spherical · vintage", [18, 25, 35, 50, 85]),
        L("Zeiss", "Standard Speed", "spherical · vintage", [16, 20, 24, 28, 32, 40, 50, 85]),
        L("Zeiss", "Supreme Prime", "spherical", [18, 21, 25, 29, 35, 50, 65, 85, 100, 135]),
        L("Zeiss", "CP.3", "spherical", [18, 21, 25, 28, 35, 50, 85, 100, 135]),
        L("ARRI", "Signature Prime", "spherical", [18, 25, 35, 47, 58, 75, 95, 125]),
        L("ARRI / Zeiss", "Master Prime", "spherical", [18, 25, 32, 40, 50, 75, 100, 135]),
        L("ARRI / Zeiss", "Ultra Prime", "spherical", [16, 20, 24, 28, 32, 40, 50, 65, 85, 100, 135]),
        L("ARRI / Zeiss", "Master Anamorphic", "anamorphic 2x", [35, 40, 50, 60, 75, 100]),
        L("Leitz", "Summilux-C", "spherical", [18, 21, 25, 29, 35, 40, 50, 65, 75, 100, 135]),
        L("Leitz", "Thalia", "spherical", [24, 30, 35, 45, 55, 70, 90, 100, 120, 180]),
        L("Panavision", "Primo", "spherical", [17.5, 21, 24, 27, 35, 40, 50, 75, 100]),
        L("Panavision", "Ultra Speed", "spherical · vintage", [24, 29, 35, 50, 85]),
        L("Panavision", "C Series", "anamorphic 2x", [35, 40, 50, 75, 100]),
        L("Atlas", "Orion", "anamorphic 2x", [21, 25, 32, 40, 50, 65, 80, 100]),
        L("Kowa", "Cine Prominar", "anamorphic 2x · vintage", [40, 50, 75, 100]),
        L("Lomo", "Roundfront", "anamorphic 2x · vintage", [35, 50, 75, 100]),
        L("Sigma", "Cine FF High Speed", "spherical", [14, 20, 24, 28, 35, 40, 50, 85, 105, 135]),
        L("Tokina", "Vista", "spherical", [18, 25, 29, 35, 40, 50, 85, 105, 135]),
        L("DZOFilm", "Vespid", "spherical", [16, 21, 25, 35, 50, 75, 100, 125]),
        L("Sony", "G Master", "spherical · stills", [24, 35, 50, 85, 135]),
        L("Angénieux", "Optimo Ultra 12x", "zoom", [24, 28, 35, 50, 70, 100, 135, 180, 240, 290], zoom: true),
        L("Angénieux", "Optimo 15–40", "zoom", [15, 18, 21, 25, 30, 35, 40], zoom: true),
        L("Fujinon", "Premista 28–100", "zoom", [28, 35, 40, 50, 65, 75, 85, 100], zoom: true),
    ]
}
