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
        switch self {
        case .aurora:
            LinearGradient(
                colors: [
                    Color(red: 0.91, green: 0.97, blue: 1.0),
                    Color(red: 0.85, green: 0.95, blue: 0.92),
                    Color(red: 0.84, green: 0.89, blue: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .graphite:
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.17, blue: 0.24),
                    Color(red: 0.21, green: 0.22, blue: 0.31)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .sunrise:
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.94, blue: 0.83),
                    Color(red: 1.0, green: 0.82, blue: 0.78),
                    Color(red: 0.99, green: 0.90, blue: 0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
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
