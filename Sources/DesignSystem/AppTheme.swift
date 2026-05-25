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
        case .ocean:
            LinearGradient(
                colors: [
                    Color(red: 0.72, green: 0.92, blue: 1.0),
                    Color(red: 0.50, green: 0.72, blue: 0.98),
                    Color(red: 0.20, green: 0.35, blue: 0.72)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .plum:
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.84, blue: 1.0),
                    Color(red: 0.70, green: 0.58, blue: 0.94),
                    Color(red: 0.32, green: 0.22, blue: 0.50)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .moss:
            LinearGradient(
                colors: [
                    Color(red: 0.88, green: 0.96, blue: 0.78),
                    Color(red: 0.64, green: 0.78, blue: 0.52),
                    Color(red: 0.25, green: 0.40, blue: 0.32)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .paper:
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.97, blue: 0.94),
                    Color(red: 0.90, green: 0.91, blue: 0.92),
                    Color(red: 0.78, green: 0.84, blue: 0.88)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .midnight:
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.06, blue: 0.10),
                    Color(red: 0.09, green: 0.12, blue: 0.22),
                    Color(red: 0.14, green: 0.20, blue: 0.35)
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
