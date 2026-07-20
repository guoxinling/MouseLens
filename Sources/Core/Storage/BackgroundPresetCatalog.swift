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
        .init(id: "aurora-air", name: "Aurora Air", kind: .wallpaper, gradient: nil, wallpaper: .init(assetName: "BackgroundAuroraAir")),
        .init(id: "sunset-bloom", name: "Sunset Bloom", kind: .wallpaper, gradient: nil, wallpaper: .init(assetName: "BackgroundSunsetBloom")),
        .init(id: "midnight-pulse", name: "Midnight Pulse", kind: .wallpaper, gradient: nil, wallpaper: .init(assetName: "BackgroundMidnightPulse")),
        .init(id: "silver-mist", name: "Silver Mist", kind: .wallpaper, gradient: nil, wallpaper: .init(assetName: "BackgroundSilverMist")),
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
