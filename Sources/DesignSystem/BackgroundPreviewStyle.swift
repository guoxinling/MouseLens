import SwiftUI

enum BackgroundPreviewStyle {
    static func makeGradient(for preset: BackgroundPreset) -> LinearGradient? {
        guard let definition = preset.gradient else { return nil }

        return LinearGradient(
            colors: definition.colors.map {
                Color(red: $0.red, green: $0.green, blue: $0.blue, opacity: $0.alpha)
            },
            startPoint: UnitPoint(x: definition.startPoint.x, y: definition.startPoint.y),
            endPoint: UnitPoint(x: definition.endPoint.x, y: definition.endPoint.y)
        )
    }

    static func wallpaperAssetName(for preset: BackgroundPreset) -> String? {
        preset.wallpaper?.assetName
    }
}

struct BackgroundPreviewFill: View {
    let preset: BackgroundPreset

    var body: some View {
        if let assetName = BackgroundPreviewStyle.wallpaperAssetName(for: preset) {
            Image(assetName)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
        } else if let gradient = BackgroundPreviewStyle.makeGradient(for: preset) {
            gradient
        } else {
            Color.clear
        }
    }
}
