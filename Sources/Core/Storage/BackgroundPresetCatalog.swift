import Foundation

struct BackgroundGradientDefinition: Equatable, Codable {
    let colors: [RGBAColor]
    let startPoint: UnitPointDefinition
    let endPoint: UnitPointDefinition
}

struct BackgroundWallpaperDefinition: Equatable, Codable {
    let assetName: String
}

struct BackgroundPreset: Identifiable, Equatable, Codable {
    enum Kind: String, Codable {
        case gradient
        case wallpaper
    }

    let id: String
    let name: String
    let kind: Kind
    let gradient: BackgroundGradientDefinition?
    let wallpaper: BackgroundWallpaperDefinition?
}

struct RGBAColor: Equatable, Codable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
}

struct UnitPointDefinition: Equatable, Codable {
    let x: Double
    let y: Double
}

enum BackgroundPresetCatalog {
    static let all: [BackgroundPreset] = [
        .init(
            id: "aurora-air",
            name: "Aurora Air",
            kind: .gradient,
            gradient: .init(
                colors: [
                    .init(red: 0.91, green: 0.97, blue: 1.0, alpha: 1),
                    .init(red: 0.85, green: 0.95, blue: 0.92, alpha: 1),
                    .init(red: 0.84, green: 0.89, blue: 1.0, alpha: 1),
                ],
                startPoint: .init(x: 0, y: 0),
                endPoint: .init(x: 1, y: 1)
            ),
            wallpaper: nil
        ),
        .init(
            id: "sunset-bloom",
            name: "Sunset Bloom",
            kind: .gradient,
            gradient: .init(
                colors: [
                    .init(red: 1.0, green: 0.93, blue: 0.82, alpha: 1),
                    .init(red: 1.0, green: 0.83, blue: 0.78, alpha: 1),
                    .init(red: 0.99, green: 0.88, blue: 0.95, alpha: 1),
                ],
                startPoint: .init(x: 0, y: 0),
                endPoint: .init(x: 1, y: 1)
            ),
            wallpaper: nil
        ),
        .init(
            id: "midnight-pulse",
            name: "Midnight Pulse",
            kind: .gradient,
            gradient: .init(
                colors: [
                    .init(red: 0.05, green: 0.06, blue: 0.10, alpha: 1),
                    .init(red: 0.09, green: 0.12, blue: 0.22, alpha: 1),
                    .init(red: 0.14, green: 0.20, blue: 0.35, alpha: 1),
                ],
                startPoint: .init(x: 0, y: 0),
                endPoint: .init(x: 1, y: 1)
            ),
            wallpaper: nil
        ),
        .init(
            id: "silver-mist",
            name: "Silver Mist",
            kind: .gradient,
            gradient: .init(
                colors: [
                    .init(red: 0.98, green: 0.97, blue: 0.94, alpha: 1),
                    .init(red: 0.90, green: 0.91, blue: 0.92, alpha: 1),
                    .init(red: 0.78, green: 0.84, blue: 0.88, alpha: 1),
                ],
                startPoint: .init(x: 0, y: 0),
                endPoint: .init(x: 1, y: 1)
            ),
            wallpaper: nil
        ),
        .init(id: "soft-glass", name: "Soft Glass", kind: .wallpaper, gradient: nil, wallpaper: .init(assetName: "BackgroundSoftGlass")),
        .init(id: "tidal-glow", name: "Tidal Glow", kind: .wallpaper, gradient: nil, wallpaper: .init(assetName: "BackgroundTidalGlow")),
        .init(id: "luminous-drift", name: "Luminous Drift", kind: .wallpaper, gradient: nil, wallpaper: .init(assetName: "BackgroundLuminousDrift")),
        .init(id: "horizon-glow", name: "Horizon Glow", kind: .wallpaper, gradient: nil, wallpaper: .init(assetName: "BackgroundHorizonGlow")),
    ]

    static let defaultPresetID = "aurora-air"

    static func preset(id: String) -> BackgroundPreset {
        all.first(where: { $0.id == id }) ?? all[0]
    }

    static func legacyPresetID(for style: ProjectBackgroundStyle) -> String {
        switch style {
        case .aurora, .ocean:
            "aurora-air"
        case .sunrise, .plum:
            "sunset-bloom"
        case .graphite, .midnight:
            "midnight-pulse"
        case .paper:
            "silver-mist"
        case .moss:
            "tidal-glow"
        }
    }

    static func legacyStyle(forPresetID presetID: String) -> ProjectBackgroundStyle {
        switch presetID {
        case "aurora-air":
            .aurora
        case "sunset-bloom":
            .sunrise
        case "midnight-pulse":
            .midnight
        case "silver-mist":
            .paper
        case "soft-glass":
            .paper
        case "tidal-glow":
            .moss
        case "luminous-drift":
            .ocean
        case "horizon-glow":
            .sunrise
        default:
            .aurora
        }
    }
}
