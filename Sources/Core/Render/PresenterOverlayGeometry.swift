import CoreGraphics

struct PresenterOverlayLayout: Equatable {
    let frame: CGRect
    let clippingPathCornerRadius: CGFloat
}

enum PresenterOverlayGeometry {
    static func layout(
        contentRect: CGRect,
        style: PresenterBubbleStyle
    ) -> PresenterOverlayLayout {
        guard style.isEnabled, contentRect.width > 0, contentRect.height > 0 else {
            return PresenterOverlayLayout(frame: .zero, clippingPathCornerRadius: 0)
        }

        let shortestSide = min(contentRect.width, contentRect.height)
        let normalizedSize = CGFloat(style.normalizedSize).clamped(to: 0...1)
        let bubbleSize = (shortestSide * normalizedSize).clamped(to: 0...shortestSide)
        let size = CGSize(width: bubbleSize, height: bubbleSize)
        let halfSize = bubbleSize / 2
        let idealCenter = CGPoint(
            x: contentRect.minX + contentRect.width * CGFloat(style.normalizedCenter.x),
            y: contentRect.minY + contentRect.height * CGFloat(style.normalizedCenter.y)
        )
        let center = CGPoint(
            x: idealCenter.x.clamped(to: (contentRect.minX + halfSize)...(contentRect.maxX - halfSize)),
            y: idealCenter.y.clamped(to: (contentRect.minY + halfSize)...(contentRect.maxY - halfSize))
        )
        let origin = CGPoint(x: center.x - halfSize, y: center.y - halfSize)
        let cornerRadius = bubbleSize * CGFloat(style.cornerRadiusRatio).clamped(to: 0...0.5)

        return PresenterOverlayLayout(
            frame: CGRect(origin: origin, size: size),
            clippingPathCornerRadius: cornerRadius
        )
    }
}
