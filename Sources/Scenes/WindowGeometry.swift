import CoreGraphics

enum WindowGeometry {
    static func centeredFrame(in visibleFrame: CGRect, scale: CGFloat = 0.7) -> CGRect {
        let size = CGSize(
            width: (visibleFrame.width * scale).rounded(.down),
            height: (visibleFrame.height * scale).rounded(.down)
        )
        return CGRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
