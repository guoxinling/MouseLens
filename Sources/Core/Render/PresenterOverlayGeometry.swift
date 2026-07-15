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
        let idealInset = max(shortestSide * 0.035, 18)
        let inset = min(idealInset, max((shortestSide - bubbleSize) / 2, 0))
        let size = CGSize(width: bubbleSize, height: bubbleSize)
        let origin: CGPoint

        switch style.position {
        case .topLeft:
            origin = CGPoint(x: contentRect.minX + inset, y: contentRect.minY + inset)
        case .topRight:
            origin = CGPoint(x: contentRect.maxX - inset - bubbleSize, y: contentRect.minY + inset)
        case .bottomLeft:
            origin = CGPoint(x: contentRect.minX + inset, y: contentRect.maxY - inset - bubbleSize)
        case .bottomRight:
            origin = CGPoint(x: contentRect.maxX - inset - bubbleSize, y: contentRect.maxY - inset - bubbleSize)
        }

        let cornerRadius: CGFloat
        switch style.shape {
        case .circle:
            cornerRadius = bubbleSize / 2
        case .roundedRect:
            cornerRadius = CGFloat(style.cornerRadius).clamped(to: 0...(bubbleSize / 2))
        }

        return PresenterOverlayLayout(
            frame: CGRect(origin: origin, size: size),
            clippingPathCornerRadius: cornerRadius
        )
    }
}
