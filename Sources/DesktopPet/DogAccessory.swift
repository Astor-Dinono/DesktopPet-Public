import AppKit

/// One mutually exclusive, optional detail. Missing/unknown preferences keep
/// the original dog; these values never alter the pet's size or hit region.
enum DogAccessory: Int, CaseIterable {
    case none = 0, scarf = 1, collar = 2
    static let preferenceKey = "dog.accessory"
    init(storedValue: Int?) { self = storedValue.flatMap(Self.init(rawValue:)) ?? .none }
    var title: String {
        switch self {
        case .none: "无"
        case .scarf: "小围巾"
        case .collar: "细项圈"
        }
    }
}

/// Immutable native paths in DogRenderer's head-local, y-up canvas. Call once
/// after the head fill/ears and before the face, inside the SAME head transform
/// used for breathing, squash, and the recorded/blended yawn. No own clock.
/// The original model has no exposed neck: the collar is deliberately just a
/// shallow lower arc and tiny side buckle, not a newly drawn neck or body.
@MainActor
enum DogAccessoryRenderer {
    struct Layer {
        let path: CGPath
        let fill: CGColor?
        let strokeWidth: CGFloat
    }

    private static let sourceScale = 260.0 / 749.0
    private static let ink = CGColor(gray: 0, alpha: 1)
    private static let scarfColor = CGColor(srgbRed: 154 / 255.0,
        green: 175 / 255.0, blue: 181 / 255.0, alpha: 1)
    private static let buckleColor = CGColor(gray: 1, alpha: 1)
    private static let collarColor = CGColor(srgbRed: 211 / 255.0,
        green: 220 / 255.0, blue: 216 / 255.0, alpha: 1)

    private static func p(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: x * sourceScale, y: (268 - y) * sourceScale + DogRenderer.baselineY)
    }

    private static let scarf: [Layer] = {
        let band = CGMutablePath()
        band.move(to: p(124, 248))
        band.addCurve(to: p(246, 263), control1: p(165, 257), control2: p(210, 262))
        band.addCurve(to: p(361, 263), control1: p(278, 265), control2: p(328, 265))
        band.addCurve(to: p(493, 247), control1: p(410, 262), control2: p(457, 256))
        band.addLine(to: p(493, 254))
        band.addCurve(to: p(361, 267), control1: p(449, 262), control2: p(409, 266))
        band.addCurve(to: p(246, 267), control1: p(320, 268), control2: p(275, 268))
        band.addCurve(to: p(124, 255), control1: p(202, 266), control2: p(155, 260))
        band.closeSubpath()
        let end = CGMutablePath()
        end.move(to: p(146, 250))
        end.addCurve(to: p(191, 248), control1: p(160, 248), control2: p(178, 247))
        end.addCurve(to: p(172, 266), control1: p(191, 253), control2: p(181, 263))
        end.addLine(to: p(152, 260)); end.closeSubpath()
        let fold = CGMutablePath()
        fold.move(to: p(146, 252))
        fold.addCurve(to: p(178, 263), control1: p(158, 253), control2: p(170, 257))
        fold.addLine(to: p(160, 266))
        fold.addCurve(to: p(136, 255), control1: p(149, 262), control2: p(140, 258))
        fold.closeSubpath()
        let knot = CGMutablePath()
        knot.move(to: p(126, 241))
        knot.addCurve(to: p(144, 245), control1: p(133, 239), control2: p(140, 241))
        knot.addCurve(to: p(158, 245), control1: p(149, 239), control2: p(156, 241))
        knot.addCurve(to: p(146, 256), control1: p(161, 251), control2: p(154, 256))
        knot.addLine(to: p(134, 255))
        knot.addCurve(to: p(126, 241), control1: p(126, 255), control2: p(122, 248))
        knot.closeSubpath()
        return [band, end, fold, knot].map { Layer(path: $0.copy()!, fill: scarfColor, strokeWidth: 1.35) }
    }()

    private static let collar: [Layer] = {
        let band = CGMutablePath()
        band.move(to: p(128, 252))
        band.addCurve(to: p(308, 266), control1: p(197, 264), control2: p(249, 266))
        band.addCurve(to: p(490, 251), control1: p(380, 266), control2: p(438, 262))
        let left = CGMutablePath()
        left.move(to: p(128, 248))
        left.addCurve(to: p(221, 262), control1: p(162, 255), control2: p(195, 260))
        left.addLine(to: p(220, 266))
        left.addCurve(to: p(128, 256), control1: p(189, 265), control2: p(157, 261))
        left.closeSubpath()
        let right = CGMutablePath()
        right.move(to: p(388, 262))
        right.addCurve(to: p(490, 247), control1: p(426, 260), control2: p(465, 254))
        right.addLine(to: p(490, 255))
        right.addCurve(to: p(389, 266), control1: p(461, 261), control2: p(426, 265))
        right.closeSubpath()
        let buckle = CGMutablePath()
        buckle.move(to: p(177, 257)); buckle.addLine(to: p(188, 259))
        buckle.addLine(to: p(186, 266)); buckle.addLine(to: p(175, 264)); buckle.closeSubpath()
        return [Layer(path: band.copy()!, fill: nil, strokeWidth: 1.45),
                Layer(path: left.copy()!, fill: collarColor, strokeWidth: 1.1),
                Layer(path: right.copy()!, fill: collarColor, strokeWidth: 1.1),
                Layer(path: buckle.copy()!, fill: buckleColor, strokeWidth: 1.15)]
    }()

    static func layers(for accessory: DogAccessory) -> [Layer] {
        switch accessory { case .none: []; case .scarf: scarf; case .collar: collar }
    }

    static func draw(_ accessory: DogAccessory, in context: CGContext) {
        guard accessory != .none else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.addPath(DogRenderer.headOutline.cgPath); context.clip()
        context.clip(to: CGRect(x: 0, y: DogRenderer.baselineY,
            width: DogRenderer.canvas.width, height: DogRenderer.canvas.height - DogRenderer.baselineY))
        context.setLineCap(.round); context.setLineJoin(.round)
        context.setStrokeColor(ink)
        for layer in layers(for: accessory) {
            context.addPath(layer.path)
            context.setLineWidth(layer.strokeWidth)
            if let fill = layer.fill {
                context.setFillColor(fill); context.drawPath(using: .fillStroke)
            } else { context.strokePath() }
        }
    }
}
