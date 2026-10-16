import CoreText
import SwiftUI
import UIKit

/// Geist and Geist Mono, with the system fonts as a fallback.
///
/// Drop Geist-Regular.ttf, Geist-Medium.ttf and GeistMono-Regular.ttf (SIL OFL, from
/// vercel.com/font) into OutAndScout/Fonts/. They are registered at launch, so no
/// Info.plist entry is needed. Until then the app uses SF Pro and SF Mono.
enum Fonts {
    static func registerBundled() {
        let urls = ["ttf", "otf"].flatMap { Bundle.main.urls(forResourcesWithExtension: $0, subdirectory: nil) ?? [] }
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// iPad sets every size a quarter bigger, so the phone layouts read at iPad distance.
    static let scale: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 1.25 : 1

    static func sans(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        let size = size * scale
        let name = weight == .medium ? "Geist-Medium" : "Geist-Regular"
        if UIFont(name: name, size: size) != nil {
            return .custom(name, fixedSize: size)
        }
        return .system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat) -> Font {
        let size = size * scale
        if UIFont(name: "GeistMono-Regular", size: size) != nil {
            return .custom("GeistMono-Regular", fixedSize: size)
        }
        return .system(size: size, weight: .regular, design: .monospaced)
    }
}
