import AppKit

enum DogOrientation: Int, CaseIterable, Sendable {
    case bottom = 0, left = 90, top = 180, right = 270

    static let preferenceKey = "dog.orientation"
    var isVertical: Bool { self == .left || self == .right }
    var title: String {
        switch self {
        case .bottom: "下边 · 0°"
        case .left: "左边 · 90°"
        case .top: "上边 · 180°"
        case .right: "右边 · 270°"
        }
    }
    var edgeTitle: String {
        switch self {
        case .bottom: "贴回屏幕底边"
        case .left: "贴回屏幕左边"
        case .top: "贴回屏幕上边"
        case .right: "贴回屏幕右边"
        }
    }
    func rotatedSize(_ size: NSSize) -> NSSize {
        isVertical ? NSSize(width: size.height, height: size.width) : size
    }
    /// Clockwise quarter turns in AppKit's y-up coordinates.
    func transform(size: NSSize) -> CGAffineTransform {
        switch self {
        case .bottom: .identity
        case .left: CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: size.width)
        case .top: CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: size.width, ty: size.height)
        case .right: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: size.height, ty: 0)
        }
    }
}

@MainActor
struct DogLayout {
    let size: NSSize
    let petFrame: NSRect
    let badgeFrame: NSRect
    let baselineAnchor: NSPoint

    init(scale: Double, orientation: DogOrientation, counterInside: Bool, badgeWidth: CGFloat = 30,
         topbarHeight: CGFloat? = nil) {
        if let topbarHeight {
            size = DogTopbarRenderer.drawingSize(scale: scale, bandHeight: topbarHeight)
            petFrame = NSRect(origin: .zero, size: size)
            badgeFrame = .zero
            baselineAnchor = NSPoint(x: size.width / 2, y: DogTopbarPlacement.baselineInset)
            return
        }
        let canonical = NSSize(width: DogRenderer.canvas.width * scale,
                               height: DogRenderer.canvas.height * scale)
        let petSize = orientation.rotatedSize(canonical)
        let footer = DogCompanionView.footerHeight
        if orientation.isVertical {
            size = NSSize(width: max(petSize.width, badgeWidth + 8), height: petSize.height + footer)
            petFrame = NSRect(x: orientation == .right ? size.width - petSize.width : 0,
                              y: footer, width: petSize.width, height: petSize.height)
        } else {
            size = NSSize(width: petSize.width, height: petSize.height + (counterInside ? 0 : footer))
            petFrame = NSRect(x: 0, y: orientation == .bottom && !counterInside ? footer : 0,
                              width: petSize.width, height: petSize.height)
        }
        let width = min(size.width - 8, max(30, badgeWidth))
        let center: CGFloat = orientation.isVertical ? size.width / 2
            : (orientation == .top ? canonical.width - 108 * scale : 108 * scale)
        let y: CGFloat
        switch orientation {
        case .bottom: y = counterInside ? 1 + 88 * scale : 2
        case .top: y = counterInside ? canonical.height - (1 + 88 * scale + 18) : canonical.height + 2
        case .left, .right: y = 2
        }
        badgeFrame = NSRect(x: min(max(4, center - width / 2), size.width - width - 4),
                            y: y, width: width, height: 18)
        let point = NSPoint(x: canonical.width / 2, y: 1 + DogRenderer.baselineY * scale)
            .applying(orientation.transform(size: canonical))
        baselineAnchor = NSPoint(x: petFrame.minX + point.x, y: petFrame.minY + point.y)
    }
}
