import SwiftUI

enum AppTheme {
    static let accent = Color(red: 0.12, green: 0.42, blue: 0.96)
    static let mutedText = Color.white.opacity(0.72)
    static let panelBorder = Color.white.opacity(0.18)
    static let windowBackground = LinearGradient(
        colors: [
            Color(red: 0.06, green: 0.08, blue: 0.18),
            Color(red: 0.04, green: 0.11, blue: 0.17),
            Color(red: 0.11, green: 0.10, blue: 0.17)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let heroGradient = LinearGradient(
        colors: [
            Color(red: 0.96, green: 0.97, blue: 1.0),
            Color(red: 0.80, green: 0.90, blue: 1.0),
            Color(red: 0.89, green: 1.0, blue: 0.92)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension ProjectBackgroundStyle {
    var gradient: LinearGradient {
        let presetID = BackgroundPresetCatalog.legacyPresetID(for: self)
        return BackgroundPresetCatalog.preset(id: presetID).previewGradient ?? AppTheme.windowBackground
    }
}

extension BackgroundPreset {
    var previewGradient: LinearGradient? {
        BackgroundPreviewStyle.makeGradient(for: self)
    }
}

extension View {
    func cardStyle() -> some View {
        self
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .strokeBorder(AppTheme.panelBorder, lineWidth: 1)
            )
    }
}
